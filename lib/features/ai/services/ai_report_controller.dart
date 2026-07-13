import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/ai_providers.dart';
import '../../../state/bills_providers.dart';
import '../../../state/dynamic_report_providers.dart';
import '../../../state/goals_providers.dart';
import '../../../state/reports_providers.dart';
import '../domain/ai_config.dart';
import '../domain/ai_gatekeeper.dart';
import '../domain/ai_payload_builder.dart';
import '../domain/ai_prompts.dart';
import '../domain/llm_client.dart';
import '../dynamic_report/chart_spec.dart';
import '../dynamic_report/default_report_spec.dart';
import '../dynamic_report/spec_validator.dart';
import 'ai_context_gatherer.dart';

/// Status of an on-demand AI report generation.
enum AiReportStatus { idle, loading, streaming, done, error }

/// State for the on-demand narrative report screen.
///
/// The report is generated in-memory only (not persisted to a chat thread) —
/// it's a one-shot, regenerable narrative. `markdown` accumulates as the LLM
/// streams so the screen can render partial output live. The gatekeeper
/// restores opaque labels → real names live and records [flagged] / [issues]
/// for the "Checked on-device" note.
class AiReportState {
  const AiReportState({
    this.status = AiReportStatus.idle,
    this.markdown = '',
    this.error,
    this.periodMonth,
    this.flagged = false,
    this.issues = const [],
  });

  final AiReportStatus status;
  final String markdown;
  final String? error;
  final DateTime? periodMonth;

  /// Whether the gatekeeper flagged the reply (leftover/invented label,
  /// leaked-PII-looking token, or out-of-range number). The text is still
  /// shown; the UI adds a small "Checked on-device" note.
  final bool flagged;
  final List<String> issues;

  /// A finished (or partially-streamed) report is available to render/export.
  bool get hasResult => markdown.isNotEmpty;

  AiReportState copyWith({
    AiReportStatus? status,
    String? markdown,
    String? error,
    DateTime? periodMonth,
    bool? flagged,
    List<String>? issues,
  }) =>
      AiReportState(
        status: status ?? this.status,
        // Allow callers to clear by passing '' explicitly.
        markdown: markdown ?? this.markdown,
        error: error,
        periodMonth: periodMonth ?? this.periodMonth,
        flagged: flagged ?? this.flagged,
        issues: issues ?? this.issues,
      );
}

/// Generates the on-demand narrative AI report.
///
/// Mirrors [AskChatNotifier]'s streaming path but for a single one-shot report
/// (no chat history, no persistence). The privacy boundary is
/// [AiPayloadBuilder.buildReportContext] — only anonymized aggregations leave
/// the device; the API key is resolved on demand via [aiConfigWithKey].
class AiReportNotifier extends StateNotifier<AiReportState> {
  AiReportNotifier(this._ref) : super(const AiReportState());
  final Ref _ref;
  StreamSubscription<String>? _sub;

  /// On-device warden for the streamed report. Restores opaque labels → real
  /// names as chunks arrive and validates the completed markdown.
  AiGatekeeper? _gatekeeper;

  /// Generate (or regenerate) the report for [month].
  Future<void> generate(DateTime month) async {
    final config = await aiConfigWithKey(_ref);
    if (config == null) {
      state = AiReportState(
        status: AiReportStatus.error,
        error: 'Add your AI API key in Settings to generate a report.',
        periodMonth: month,
      );
      return;
    }

    state = AiReportState(
      status: AiReportStatus.loading,
      periodMonth: month,
    );

    Map<String, Object?> context;
    try {
      context = await _buildContext(config, month);
    } catch (e) {
      state = AiReportState(
        status: AiReportStatus.error,
        error: 'Could not load report data: $e',
        periodMonth: month,
      );
      return;
    }

    // Resolve the chart spec (Phase 2). With `aiSpecEnabled` off, or on any
    // failure, this keeps the safe default spec — charts always render. The
    // result is pushed to [reportSpecProvider] so the screen's charts re-render
    // from real, on-device data. The LLM never sees raw rows.
    final spec = await _resolveSpec(config, context);
    _ref.read(reportSpecProvider.notifier).state = spec;

    // `narrativeSeed` stays in opaque-label form (see SpecValidator) so sending
    // it outbound leaks no real names. The LLM is told these are opaque labels;
    // any it echoes into the narrative are restored to real names on-device by
    // the AiGatekeeper during streaming.
    final seedHint = spec.narrativeSeed == null || spec.narrativeSeed!.isEmpty
        ? ''
        : '\n\nA suggested focus for the narrative (use opaque labels like '
            'cat_0 verbatim — they are restored to real names on-device): '
            '${spec.narrativeSeed}';
    // Chart menu for inline placement. Built from the `DataProvider` enum +
    // index only — no real names, opaque labels, or amounts leave the device.
    // The LLM uses these indices in `{{chart:N}}` markers; the app renders the
    // matching on-device chart at that point in the streamed narrative.
    final chartMenu = _chartMenu(spec.charts);
    final messages = [
      const ChatMessage(role: 'system', content: kReportSystemPrompt),
      ChatMessage(
        role: 'user',
        content:
            'Here is my anonymized financial summary for context (JSON). Write '
            'the report using ONLY this data:\n'
            '${const JsonEncoder.withIndent('  ').convert(context)}'
            '$seedHint'
            '$chartMenu',
      ),
    ];

    state = state.copyWith(
      status: AiReportStatus.streaming,
      markdown: '',
    );

    await _sub?.cancel();
    final client = _ref.read(aiClientProvider);
    _sub = client.stream(config, messages, maxTokens: 3072).listen(
      (chunk) {
        if (!mounted) return;
        // Live-restore opaque labels → real names as the report streams in.
        final restored = _gatekeeper?.restore(chunk) ?? chunk;
        state = state.copyWith(
          status: AiReportStatus.streaming,
          markdown: state.markdown + restored,
        );
      },
      onError: (Object e) {
        if (!mounted) return;
        state = state.copyWith(
          status: AiReportStatus.error,
          error: _errorMessage(e),
        );
      },
      onDone: () {
        if (!mounted) return;
        if (state.status != AiReportStatus.streaming) return;
        // Gatekeeper check on the completed (already-restored) report.
        final check = _gatekeeper?.check(state.markdown) ??
            (issues: const <String>[], severity: AiCheckSeverity.ok);
        if (check.severity == AiCheckSeverity.bad) {
          state = state.copyWith(
            status: AiReportStatus.error,
            error: check.issues.join(' '),
            flagged: false,
            issues: check.issues,
          );
          return;
        }
        state = state.copyWith(
          status: AiReportStatus.done,
          flagged: check.severity == AiCheckSeverity.flagged,
          issues: check.issues,
        );
      },
    );
  }

  /// Re-run for the currently-selected period (if any).
  Future<void> regenerate() async {
    final m = state.periodMonth;
    if (m != null) await generate(m);
  }

  /// Reset to idle (clears the generated report).
  void clear() {
    _sub?.cancel();
    state = const AiReportState();
    // Reset charts to the safe default so a stale LLM spec doesn't outlive the
    // report it was generated for.
    _ref.read(reportSpecProvider.notifier).state = defaultReportSpec;
  }

  /// Gather the month's aggregations and build the anonymized report context.
  /// Reads from the shared [aiReportDataProvider] so the charts and the AI
  /// narrative see identical data. Also builds the on-device [AiGatekeeper]
  /// from the returned legend so the streamed report can be label-restored +
  /// checked before display.
  Future<Map<String, Object?>> _buildContext(
      AiConfig config, DateTime month) async {
    final data = await _ref
        .read(aiReportDataProvider((month.year, month.month)).future);

    final extras = await gatherAiContextExtras(
      reports: _ref.read(reportsRepositoryProvider),
      goalsRepo: _ref.read(goalsRepositoryProvider),
      recurringRepo: _ref.read(recurringRepositoryProvider),
      year: month.year,
      month: month.month,
    );

    final builder = AiPayloadBuilder(shareNames: config.shareNames);
    final ctx = builder.buildReportContext(
      summary: data.summary,
      budgets: data.budgets,
      cashflow: data.cashflow,
      topExpenseCategories: data.topExpenseCategories,
      modeBreakdown: data.modes,
      period: '${month.year}-${month.month.toString().padLeft(2, '0')}',
      accountBalances: extras.accountBalances,
      tagBreakdown: extras.tagBreakdown,
      categoryBreakdown3mo: extras.categoryBreakdown3mo,
      expenseCount: extras.expenseCount,
      daysInPeriod: extras.daysInPeriod,
      dailyExpenseByDay: extras.dailyExpenseByDay,
      goals: extras.goals,
      recurringBills: extras.recurringBills,
    );
    final topCatsTotal =
        data.topExpenseCategories.fold<double>(0.0, (a, c) => a + c.total);
    // sentAmounts = every figure in the outbound JSON, so the gatekeeper can
    // flag any reply number that matches nothing we sent. sentNameVocabulary
    // is only populated when names were shared (anonymized mode sends none).
    _gatekeeper = AiGatekeeper(
      legend: ctx.legend,
      validLabels: ctx.legend.keys.toSet(),
      maxContextAmount: [
        data.summary.income,
        data.summary.expense,
        data.summary.closingBalance,
        topCatsTotal,
      ].fold<double>(0.0, max),
      sentAmounts: AiPayloadBuilder.collectAmounts(ctx.json),
      sentNameVocabulary:
          config.shareNames ? ctx.legend.values.toSet() : null,
    );
    return ctx.json;
  }

  /// Resolve the chart spec for this report.
  ///
  /// - `aiSpecEnabled` off → the safe [defaultReportSpec] (no LLM call).
  /// - on → ask the LLM to emit a `DynamicReportSpec` (JSON mode), validate with
  ///   [SpecValidator] (the gatekeeper restores opaque labels in titles on
  ///   device), and on validation failure retry once feeding the errors back.
  ///   On a second failure (or any error), fall back to the default — the
  ///   report is never blocked by a bad spec.
  ///
  /// Privacy: the LLM sees only the spec system prompt (which embeds the frozen
  /// schema metadata) + the anonymized context (opaque labels + aggregates). It
  /// never sees raw rows or real amounts; the spec it returns only references
  /// named on-device providers. `customSqlEnabled` follows the user's opt-in
  /// setting and is also surfaced in the context so the LLM knows whether
  /// `customSql` is available.
  Future<DynamicReportSpec> _resolveSpec(
      AiConfig config, Map<String, Object?> context) async {
    if (!_ref.read(aiSpecEnabledProvider) || _gatekeeper == null) {
      return defaultReportSpec;
    }
    final customSql = _ref.read(aiCustomSqlProvider);
    final validator = SpecValidator(
      gatekeeper: _gatekeeper,
      customSqlEnabled: customSql,
    );
    final specContext = <String, Object?>{
      ...context,
      'customSqlEnabled': customSql,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(specContext);
    var messages = <ChatMessage>[
      const ChatMessage(role: 'system', content: kReportSpecSystemPrompt),
      ChatMessage(
        role: 'user',
        content: 'Here is my anonymized financial summary (JSON). Propose '
            'charts using ONLY this data:\n$encoded',
      ),
    ];
    final client = _ref.read(aiClientProvider);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final raw = await client.complete(config, messages,
            maxTokens: 1024, json: true);
        final result = validator.parse(raw);
        if (result is ValidSpec) return result.spec;
        if (attempt == 0) {
          final errs = (result as InvalidSpec).errors.join('; ');
          messages = [
            ...messages,
            ChatMessage(role: 'assistant', content: raw),
            ChatMessage(
              role: 'user',
              content: 'That response was not valid: $errs. Respond with ONLY '
                  'a corrected JSON object matching the schema — no prose, no '
                  'markdown fences.',
            ),
          ];
        } else {
          break;
        }
      } catch (_) {
        break; // network/provider error → default spec, narrative still works
      }
    }
    return defaultReportSpec;
  }

  String _errorMessage(Object e) =>
      e is LlmException ? e.userMessage : 'Something went wrong. Try again.';

  /// Builds the inline-chart menu appended to the narrative user message.
  ///
  /// Returns an empty string when there are no charts. Each entry is
  /// `"<index>: <provider> (<short description>)"` — the description is a
  /// static per-provider phrase, NOT derived from any user data, so this leaks
  /// no PII. The LLM references these indices via `{{chart:N}}` markers.
  String _chartMenu(List<ChartSpec> charts) {
    if (charts.isEmpty) return '';
    final entries = <String>[];
    for (var i = 0; i < charts.length; i++) {
      entries.add('$i: ${charts[i].provider.name} (${_providerDesc(charts[i].provider)})');
    }
    return '\n\nAvailable on-device charts (place inline with {{chart:N}}, N '
        'is the index): ${entries.join(', ')}.';
  }

  String _providerDesc(DataProvider p) => switch (p) {
        DataProvider.topCategories => 'where your money went',
        DataProvider.cashflow6mo => '6-month income vs expense trend',
        DataProvider.budgets => 'budget progress for the month',
        DataProvider.modes => 'payment-mode breakdown',
        DataProvider.monthlySummary => 'month at a glance: income/expense/net',
        DataProvider.customSql => 'custom data view',
      };

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Non-autoDispose so the generated report survives a detour to `/ai/settings`
/// (and back) without regenerating. One notifier for the app session.
final aiReportProvider =
    StateNotifierProvider<AiReportNotifier, AiReportState>(
        (ref) => AiReportNotifier(ref));