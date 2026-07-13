import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/ai_providers.dart';
import '../../../state/home_providers.dart';
import '../../../state/reports_providers.dart';
import '../domain/ai_gatekeeper.dart';
import '../domain/ai_prompts.dart';
import '../domain/insight_anonymizer.dart';
import '../domain/local_insight_engine.dart';
import '../domain/llm_client.dart';

/// State for the on-demand insight-polish pass.
class AiPolishState {
  const AiPolishState({this.polished, this.loading = false, this.error, this.flagged = false});

  /// The polished insights, or null when not yet polished / idle / failed.
  final List<AiInsight>? polished;
  final bool loading;
  final String? error;

  /// Whether the on-device gatekeeper flagged one or more polished insights
  /// (an invented label, leaked-looking PII, or an out-of-range figure). The
  /// text is still shown; the UI adds a "Checked on-device" note.
  final bool flagged;

  /// Idle = not requested and not loading.
  bool get isIdle => polished == null && !loading && error == null;

  static const idle = AiPolishState();
}

/// On-demand LLM polish for the local smart insights.
///
/// Triggered explicitly by the "Get AI coaching on these" button (not
/// automatic, to control token usage). The local [AiInsight] text is
/// anonymized via [InsightAnonymizer] before it leaves the device — only
/// opaque labels (`cat_0`, `mode_1`) and the already-computed figures are sent.
/// The LLM's rewritten text is restored to real names on-device, keeping each
/// original insight's severity + emoji. On any failure, the UI falls back to
/// the local insights.
class AiInsightPolishNotifier extends StateNotifier<AiPolishState> {
  AiInsightPolishNotifier(this._ref) : super(AiPolishState.idle);
  final Ref _ref;

  Future<void> polish() async {
    if (state.loading) return;
    state = const AiPolishState(loading: true);

    try {
      final local = await _ref.read(aiInsightsProvider.future);
      if (local.isEmpty) {
        state = AiPolishState.idle;
        return;
      }

      final config = await aiConfigWithKey(_ref);
      if (config == null) {
        state = const AiPolishState(error: 'Add your AI API key in Settings.');
        return;
      }

      final vocab = await _buildVocabulary();
      final anonymizer = InsightAnonymizer(
        categories: vocab.categories,
        modes: vocab.modes,
      );
      final anon = anonymizer.anonymizeInsights(local);

      final userMessage = jsonEncode(anon
          .map((t) => {'title': t.title, 'body': t.body})
          .toList());

      final client = _ref.read(aiClientProvider);
      final reply = await client.complete(
        config,
        [
          const ChatMessage(
              role: 'system', content: kInsightPolishSystemPrompt),
          ChatMessage(
              role: 'user',
              content:
                  'Rewrite each of these local insights as a clearer, actionable '
                  'coaching nudge. Return ONLY a JSON array of {"title","body"} '
                  'objects in the same order and count:\n$userMessage'),
        ],
        maxTokens: 1500,
      );

      final parsed = _parseReply(reply, expected: local.length);

      // Route the polished text through the on-device gatekeeper (built from
      // the InsightAnonymizer legend + the figures embedded in the local
      // insights) so it is restored AND checked — PII-scrub + numeric sanity
      // now apply to the polish path for the first time, mirroring chat/report.
      // Names were never sent (always anonymized), so sentNameVocabulary is
      // null and the hallucinated-name check is skipped.
      final sentAmounts = _amountsFromInsights(local);
      final maxAmount = sentAmounts.fold<double>(0.0, max);
      final gatekeeper = AiGatekeeper(
        legend: anonymizer.labelToName,
        validLabels: anonymizer.labelToName.keys.toSet(),
        maxContextAmount: maxAmount > 0 ? maxAmount : null,
        sentAmounts: sentAmounts,
      );

      var flagged = false;
      final polished = <AiInsight>[];
      for (var i = 0; i < local.length; i++) {
        final orig = local[i];
        final title = gatekeeper.restore(parsed[i].title);
        final body = gatekeeper.restore(parsed[i].body);
        final check = gatekeeper.check('$title $body');
        if (check.severity == AiCheckSeverity.bad) {
          // Garbage reply → fall back to local insights (polished = null).
          state = AiPolishState(error: check.issues.join(' '));
          return;
        }
        if (check.severity == AiCheckSeverity.flagged) flagged = true;
        polished.add(AiInsight(
          title: title,
          body: body,
          severity: orig.severity,
          emoji: orig.emoji,
        ));
      }
      state = AiPolishState(polished: polished, flagged: flagged);
    } on LlmException catch (e) {
      state = AiPolishState(error: e.userMessage);
    } catch (e) {
      // Parse failure or anything else → fall back to local (error shown, UI
      // keeps showing the local insights).
      state = AiPolishState(error: 'Could not polish insights: $e');
    }
  }

  /// Pull every numeric figure out of the local insight text — these are the
  /// amounts the LLM saw (anonymization changes names, not numbers) — so the
  /// gatekeeper can flag any polished figure that matches nothing sent.
  Set<double> _amountsFromInsights(List<AiInsight> insights) {
    final amounts = <double>{};
    final re = RegExp(r'\d[\d,]*(?:\.\d+)?');
    for (final i in insights) {
      for (final t in [i.title, i.body]) {
        for (final m in re.allMatches(t)) {
          final n = double.tryParse(m.group(0)!.replaceAll(',', ''));
          if (n != null) amounts.add(n);
        }
      }
    }
    return amounts;
  }

  /// Reset to idle (clears polished results).
  void reset() {
    state = AiPolishState.idle;
  }

  /// Collect every category + mode name that could appear in any local insight:
  /// the 6-month expense export (covers spike + recurring detectors) plus the
  /// current month's budget categories.
  Future<({Set<String> categories, Set<String> modes})> _buildVocabulary() async {
    final repo = _ref.read(reportsRepositoryProvider);
    final budgetsRepo = _ref.read(budgetsRepositoryProvider);
    final now = DateTime.now();
    final recStart = DateTime(now.year, now.month - 5);
    final from = DateTime(recStart.year, recStart.month).toIso8601String();
    final to = DateTime(now.year, now.month + 1).toIso8601String();

    final rows = await repo.transactionsForExport(
        from: from, to: to, kind: 'expense');
    final categories = <String>{};
    final modes = <String>{};
    for (final r in rows) {
      if (r.categoryName.trim().isNotEmpty) categories.add(r.categoryName);
      if (r.modeName.trim().isNotEmpty) modes.add(r.modeName);
    }

    final budgets =
        await budgetsRepo.progressForMonth(DateTime(now.year, now.month));
    for (final b in budgets) {
      if (b.categoryName.trim().isNotEmpty) categories.add(b.categoryName);
    }
    return (categories: categories, modes: modes);
  }

  /// Parse the LLM reply as a JSON array of {title, body}. Throws on any shape
  /// or count mismatch so the caller falls back to local insights.
  List<InsightText> _parseReply(String reply, {required int expected}) {
    final decoded = jsonDecode(reply.trim());
    if (decoded is! List) {
      throw const FormatException('Expected a JSON array');
    }
    if (decoded.length != expected) {
      throw FormatException('Expected $expected items, got ${decoded.length}');
    }
    final out = <InsightText>[];
    for (final item in decoded) {
      if (item is! Map) throw const FormatException('Array item is not an object');
      final title = item['title'];
      final body = item['body'];
      if (title is! String || body is! String) {
        throw const FormatException('Missing string title/body');
      }
      out.add((title: title, body: body));
    }
    return out;
  }
}

/// AutoDispose: the polished state is per-visiting-the-Reports-screen and
/// resets when the section unmounts, so a stale polished set never lingers
/// after the underlying insights change elsewhere.
final aiPolishedInsightsProvider =
    StateNotifierProvider.autoDispose<AiInsightPolishNotifier, AiPolishState>(
        (ref) => AiInsightPolishNotifier(ref));