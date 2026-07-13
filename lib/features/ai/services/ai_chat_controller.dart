import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../data/models/budget_progress.dart';
import '../../../data/models/report_models.dart';
import '../../../state/ai_providers.dart';
import '../../../state/bills_providers.dart';
import '../../../state/database_provider.dart';
import '../../../state/goals_providers.dart';
import '../../../state/home_providers.dart';
import '../../../state/reports_providers.dart';
import '../domain/ai_config.dart';
import '../domain/ai_gatekeeper.dart';
import '../domain/ai_mention_resolver.dart';
import '../domain/ai_payload_builder.dart';
import '../domain/ai_prompts.dart';
import '../domain/llm_client.dart';
import 'ai_context_gatherer.dart';

/// A visible chat message. `id` is the persisted DB row id ('' for transient
/// bubbles like errors that are never stored); `createdAt` is the ms timestamp
/// used to locate a message when editing/truncating.
class AskMessage {
  const AskMessage({
    required this.role,
    required this.content,
    this.id = '',
    this.createdAt = 0,
    this.streaming = false,
    this.isError = false,
  });
  final String role; // 'user' | 'assistant'
  final String content;
  final String id;
  final int createdAt;
  final bool streaming;
  final bool isError;

  AskMessage copyWith({
    String? content,
    bool? streaming,
    bool? isError,
  }) =>
      AskMessage(
        role: role,
        content: content ?? this.content,
        id: id,
        createdAt: createdAt,
        streaming: streaming ?? this.streaming,
        isError: isError ?? this.isError,
      );
}

class AskConversationState {
  const AskConversationState({
    this.messages = const [],
    this.isLoading = false,
  });
  final List<AskMessage> messages;
  final bool isLoading;

  AskConversationState copyWith({
    List<AskMessage>? messages,
    bool? isLoading,
  }) =>
      AskConversationState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Drives one AI Copilot chat thread, keyed by thread id.
///
/// Messages are loaded from Drift on creation and every user message + each
/// completed assistant reply is persisted, so a conversation survives close and
/// can be continued, edited-and-regenerated, or deleted. The hidden system +
/// anonymized-context preamble is rebuilt in memory per notifier instance and
/// re-injected on the first action of a session (the LLM has no cross-session
/// memory; the context is cheap and contains no PII).
///
/// The privacy boundary lives in [AiPayloadBuilder] (called by [_buildContext])
/// — only anonymized aggregations ever leave the device.
final askChatProvider =
    StateNotifierProvider.autoDispose.family<AskChatNotifier, AskConversationState, String>(
  (ref, threadId) => AskChatNotifier(ref, threadId),
);

class AskChatNotifier extends StateNotifier<AskConversationState> {
  AskChatNotifier(this._ref, this._threadId) : super(const AskConversationState()) {
    _loadMessages();
  }

  final Ref _ref;
  final String _threadId;

  /// Hidden preamble (system + context + ack) built once on the first action
  /// of a session. Not persisted — rebuilt per session.
  List<ChatMessage> _preamble = const [];
  bool _contextSent = false;
  StreamSubscription<String>? _sub;

  /// On-device warden for the LLM's replies. Built alongside the preamble from
  /// the [AiPayloadBuilder] legend (which never leaves the device). Restores
  /// opaque labels → real names live as chunks arrive, and validates the
  /// completed reply before it is persisted. Rebuilt per stream so the
  /// per-question mention amounts/names can be merged into its checks.
  AiGatekeeper? _gatekeeper;

  /// Resolves the user's real-name mentions (e.g. "fuel") to the anonymized
  /// labels/figures the LLM holds, on-device, so the AI can answer about a
  /// category the user names without the legend ever leaving. Built once per
  /// session alongside the preamble.
  AiMentionResolver? _resolver;

  // Base gatekeeper params (stable for the session); the per-stream gatekeeper
  // is rebuilt from these + the current question's resolved mentions.
  Map<String, String> _legend = const {};
  Set<String> _validLabels = const {};
  double? _maxContextAmount;
  Set<double> _baseAmounts = const {};
  bool _shareNames = false;

  bool get canUseAi => _ref.read(aiEnabledProvider);

  // ── Load persisted history on open ───────────────────────────────────────

  Future<void> _loadMessages() async {
    final rows = await _ref.read(aiChatRepositoryProvider).getMessages(_threadId);
    if (!mounted) return;
    state = state.copyWith(messages: rows.map(_toAskMessage).toList());
  }

  AskMessage _toAskMessage(AiMessage m) => AskMessage(
        role: m.role,
        content: m.content,
        id: m.id,
        createdAt: m.createdAt,
        isError: m.isError,
      );

  // ── Public actions ──────────────────────────────────────────────────────

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (state.isLoading || trimmed.isEmpty) return;
    if (!canUseAi) {
      state = state.copyWith(messages: [
        ...state.messages,
        AskMessage(role: 'user', content: trimmed),
        const AskMessage(
            role: 'assistant',
            content:
                'AI Copilot is turned off. Enable it and add an API key in Settings.',
            isError: true),
      ]);
      return;
    }

    final saved =
        await _ref.read(aiChatRepositoryProvider).addUserMessage(_threadId, trimmed);
    state = state.copyWith(messages: [
      ...state.messages,
      AskMessage(
          role: 'user', content: trimmed, id: saved.id, createdAt: saved.createdAt),
    ]);
    await _streamReply();
  }

  /// Re-run the assistant reply for the last user message without retyping.
  Future<void> regenerateLast() async {
    if (state.isLoading) return;
    if (!canUseAi) {
      _failLast('AI Copilot is turned off. Enable it and add an API key in Settings.');
      return;
    }
    final msgs = state.messages;
    if (msgs.isEmpty) return;
    final last = msgs.last;
    if (last.role != 'assistant' || last.id.isEmpty) return;

    // Drop the old reply (DB + memory). It's an assistant message, so the
    // repo only removes that one row.
    final repo = _ref.read(aiChatRepositoryProvider);
    await repo.deleteMessage(last.id);
    state = state.copyWith(
        messages: msgs.where((m) => m.id != last.id).toList());
    await _streamReply();
  }

  /// Edit a past *user* message and regenerate from that point: truncate
  /// everything after it, update its content, then re-run.
  Future<void> editAndResend(String messageId, String newText) async {
    final trimmed = newText.trim();
    if (state.isLoading || trimmed.isEmpty) return;
    if (!canUseAi) {
      _failLast('AI Copilot is turned off. Enable it and add an API key in Settings.');
      return;
    }

    final idx = state.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final target = state.messages[idx];
    if (target.role != 'user') return; // only user messages are editable

    final repo = _ref.read(aiChatRepositoryProvider);
    await repo.deleteMessagesAfter(_threadId, target.createdAt);
    await repo.updateMessageContent(messageId, trimmed);

    final newMessages = List<AskMessage>.of(state.messages.sublist(0, idx + 1));
    newMessages[idx] = target.copyWith(content: trimmed);
    state = state.copyWith(messages: newMessages);
    await _streamReply();
  }

  /// Delete a single message (and, for a user message, its paired reply) from
  /// both the DB and the in-memory list.
  Future<void> deleteMessage(String messageId) async {
    await _ref.read(aiChatRepositoryProvider).deleteMessage(messageId);
    if (!mounted) return;
    // The repo may remove one or two rows (user + its reply); drop both by id
    // and any reply that immediately followed the user message in memory.
    final msgs = state.messages;
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final target = msgs[idx];
    final removeIds = {messageId};
    if (target.role == 'user' &&
        idx + 1 < msgs.length &&
        msgs[idx + 1].role == 'assistant') {
      removeIds.add(msgs[idx + 1].id);
    }
    state = state.copyWith(
        messages: msgs.where((m) => !removeIds.contains(m.id)).toList());
  }

  // ── Streaming ───────────────────────────────────────────────────────────

  /// Common path: ensure the anonymized preamble exists, append a placeholder,
  /// stream the reply, and persist the completed assistant message.
  Future<void> _streamReply() async {
    final config = await _aiConfigWithKey();
    if (config == null) {
      _failLast('Add your AI API key in Settings to use this.');
      return;
    }

    if (!_contextSent) {
      final context = await _buildContext(config);
      _preamble = [
        ChatMessage(role: 'system', content: kAskSystemPrompt),
        ChatMessage(
            role: 'user',
            content:
                'Here is my anonymized financial summary for context (JSON). '
                'Use only this data to answer my questions:\n'
                '${const JsonEncoder.withIndent('  ').convert(context)}'),
        ChatMessage(
            role: 'assistant',
            content: 'Got it — I have your summary. What would you like to know?'),
      ];
      _contextSent = true;
    }

    // History = all persisted (non-placeholder) messages so far.
    final history = state.messages
        .map((m) => ChatMessage(role: m.role, content: m.content))
        .toList();

    // Resolve the user's real-name mentions in their latest question (e.g.
    // "fuel" → cat_3 / its current-month amount) ON-DEVICE, and append a
    // `[Context note]` to that user message **as sent to the LLM only** — it is
    // never persisted and never shown in the UI. This bridges the gap between
    // the user's real names and the anonymized labels the LLM holds, without
    // leaking the legend (only names the user typed are reused). Also rebuild
    // the gatekeeper so a reply quoting the note's figures/names passes.
    final resolution = _resolveLastUserMessage(history);
    if (resolution != null) {
      _gatekeeper =
          _buildGatekeeper(resolution.amounts, resolution.matchedNames);
    }

    final requestMessages = [..._preamble, ...history];

    state = state.copyWith(
      messages: [
        ...state.messages,
        const AskMessage(role: 'assistant', content: '', streaming: true),
      ],
      isLoading: true,
    );

    await _sub?.cancel();
    final client = _ref.read(aiClientProvider);
    _sub = client.stream(config, requestMessages).listen(
      _onChunk,
      onError: (Object e) => _failLast(_errorMessage(e)),
      onDone: () {
        if (state.isLoading) _finishLast();
      },
    );
  }

  void _onChunk(String chunk) {
    final messages = List<AskMessage>.of(state.messages);
    if (messages.isEmpty || messages.last.role != 'assistant') return;
    final last = messages.last;
    // Live-restore opaque labels → real names as text streams in. Safe on
    // partial text: word-boundary matching means a half-arrived "cat_" won't
    // match until the full "cat_0" token is present.
    final restored = _gatekeeper?.restore(chunk) ?? chunk;
    messages[messages.length - 1] =
        last.copyWith(content: last.content + restored);
    state = state.copyWith(messages: messages);
  }

  Future<void> _finishLast() async {
    final messages = List<AskMessage>.of(state.messages);
    if (messages.isEmpty || !messages.last.streaming) {
      state = state.copyWith(isLoading: false);
      return;
    }
    final last = messages.last;
    // Some providers send no chunks → drop the empty placeholder entirely.
    if (last.content.isEmpty) {
      messages.removeLast();
      state = state.copyWith(messages: messages, isLoading: false);
      return;
    }
    // Gatekeeper check on the completed (already-restored) reply. `bad` = empty
    // / garbage → surface an error bubble and do NOT persist.
    final check = _gatekeeper?.check(last.content) ??
        (issues: const <String>[], severity: AiCheckSeverity.ok);
    if (check.severity == AiCheckSeverity.bad) {
      messages[messages.length - 1] = AskMessage(
        role: 'assistant',
        content: check.issues.join(' '),
        isError: true,
      );
      state = state.copyWith(messages: messages, isLoading: false);
      return;
    }
    // Persist the completed (restored) reply so reloaded history shows real
    // names, not the opaque labels the LLM saw.
    final saved = await _ref
        .read(aiChatRepositoryProvider)
        .addAssistantMessage(_threadId, last.content);
    if (!mounted) return;
    messages[messages.length - 1] = AskMessage(
      role: 'assistant',
      content: last.content,
      id: saved.id,
      createdAt: saved.createdAt,
      streaming: false,
    );
    state = state.copyWith(messages: messages, isLoading: false);
  }

  /// Show a transient (non-persisted) error bubble. If a partial reply already
  /// streamed, keep it and append the error as a separate bubble.
  void _failLast(String message) {
    final messages = List<AskMessage>.of(state.messages);
    if (messages.isNotEmpty && messages.last.streaming) {
      final last = messages.last;
      if (last.content.isEmpty) {
        messages[messages.length - 1] =
            AskMessage(role: 'assistant', content: message, isError: true);
      } else {
        messages[messages.length - 1] = last.copyWith(streaming: false);
        messages.add(AskMessage(role: 'assistant', content: message, isError: true));
      }
    } else {
      messages.add(AskMessage(role: 'assistant', content: message, isError: true));
    }
    state = state.copyWith(messages: messages, isLoading: false);
  }

  Future<AiConfig?> _aiConfigWithKey() => aiConfigWithKey(_ref);

  /// Resolve the latest user message in [history] and, if it mentions any known
  /// entity, append the `[Context note]` hint to that message in-place. Returns
  /// the resolution (for gatekeeper augmentation) or null if there is no
  /// resolver yet (e.g. AI off / context not built) or no mentions.
  AiMentionResolution? _resolveLastUserMessage(List<ChatMessage> history) {
    final resolver = _resolver;
    if (resolver == null) return null;
    // Find the most recent user message (the question being answered).
    int? lastUserIdx;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].role == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx == null) return null;
    final original = history[lastUserIdx].content;
    final resolution = resolver.resolve(original);
    if (!resolution.hasMentions) return null;
    history[lastUserIdx] =
        ChatMessage(role: 'user', content: original + resolution.hint);
    return resolution;
  }

  /// Fetches the current month's aggregations and builds the anonymized
  /// context. This is the only place data is gathered to send to the LLM.
  /// Also builds the on-device [AiGatekeeper] from the returned legend so
  /// replies can be label-restored + checked before display.
  Future<Map<String, Object?>> _buildContext(AiConfig config) async {
    final repo = _ref.read(reportsRepositoryProvider);
    final budgetsRepo = _ref.read(budgetsRepositoryProvider);
    final now = DateTime.now();
    final monthDate = DateTime(now.year, now.month);
    final from = monthDate.toIso8601String();
    final to = DateTime(now.year, now.month + 1).toIso8601String();

    final MonthlySummary summary = await repo.monthlySummary(now.year, now.month);
    final List<BudgetProgress> budgets =
        await budgetsRepo.progressForMonth(monthDate);
    final List<MonthTotal> cashflow = await repo.cashFlowMonths(count: 12);
    final List<ModeTotal> modes =
        await repo.modeBreakdown(from: from, to: to, kind: 'expense');

    final extras = await gatherAiContextExtras(
      reports: repo,
      goalsRepo: _ref.read(goalsRepositoryProvider),
      recurringRepo: _ref.read(recurringRepositoryProvider),
      year: now.year,
      month: now.month,
    );

    // Full entity directory (on-device only) — reused both for mention
    // resolution and now for the payload's all-categories/modes/tags.
    final mentionData = await gatherAiMentionData(
      db: _ref.read(appDatabaseProvider),
      modeBreakdown: modes,
      extras: extras,
    );

    final builder = AiPayloadBuilder(shareNames: config.shareNames);
    final ctx = builder.buildAskContext(
      summary: summary,
      budgets: budgets,
      cashflow: cashflow,
      period: '${now.year}-${now.month.toString().padLeft(2, '0')}',
      modeBreakdown: modes,
      accountBalances: extras.accountBalances,
      tagBreakdown: extras.tagBreakdown,
      categoryBreakdown3mo: extras.categoryBreakdown3mo,
      expenseCount: extras.expenseCount,
      daysInPeriod: extras.daysInPeriod,
      dailyExpenseByDay: extras.dailyExpenseByDay,
      goals: extras.goals,
      recurringBills: extras.recurringBills,
      allCategories: mentionData.categories,
      allModes: mentionData.modes,
      allTags: mentionData.tags,
    );
    _resolver = AiMentionResolver(data: mentionData, legend: ctx.legend);

    // Store the stable gatekeeper base; the per-stream gatekeeper is rebuilt
    // from these + the current question's resolved mentions (so a reply that
    // quotes a mention's figure/name isn't flagged as hallucinated).
    _legend = ctx.legend;
    _validLabels = ctx.legend.keys.toSet();
    _maxContextAmount =
        [summary.income, summary.expense, summary.closingBalance]
            .fold<double>(0.0, max);
    _baseAmounts = AiPayloadBuilder.collectAmounts(ctx.json);
    _shareNames = config.shareNames;
    _gatekeeper = _buildGatekeeper(const {}, const []);
    return ctx.json;
  }

  /// Build the on-device warden for one stream. [mentionAmounts] are figures
  /// the per-question `[Context note]` introduced (so a reply quoting them is
  /// accepted, not flagged). [mentionNames] are the real names the user typed
  /// that the note tied to labels — in `shareNames` mode they're added to the
  /// vocabulary so a reply using a mentioned-but-not-top-5 name isn't flagged
  /// as invented.
  AiGatekeeper _buildGatekeeper(
      Set<double> mentionAmounts, List<String> mentionNames) {
    final amounts = {..._baseAmounts, ...mentionAmounts};
    return AiGatekeeper(
      legend: _legend,
      validLabels: _validLabels,
      maxContextAmount: _maxContextAmount,
      sentAmounts: amounts,
      sentNameVocabulary: _shareNames
          ? {..._legend.values, ...mentionNames}
          : null,
    );
  }

  String _errorMessage(Object e) =>
      e is LlmException ? e.userMessage : 'Something went wrong. Try again.';

  @override
  void dispose() {
    _sub?.cancel();
    // Prune an empty thread (opened a new chat and left without sending).
    _pruneIfEmpty();
    super.dispose();
  }

  Future<void> _pruneIfEmpty() async {
    try {
      final repo = _ref.read(aiChatRepositoryProvider);
      final count = await repo.countMessages(_threadId);
      if (count == 0) await repo.deleteThread(_threadId);
    } catch (_) {
      // Best-effort cleanup; never crash on dispose.
    }
  }
}