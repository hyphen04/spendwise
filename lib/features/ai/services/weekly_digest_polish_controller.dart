import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/ai_providers.dart';
import '../../../state/app_mode_providers.dart';
import '../../../state/digest_providers.dart';
import '../../../state/reports_providers.dart';
import '../domain/ai_gatekeeper.dart';
import '../domain/ai_prompts.dart';
import '../domain/insight_anonymizer.dart';
import '../domain/local_insight_engine.dart';
import '../domain/llm_client.dart';
import '../../digest/weekly_digest.dart';

/// State for the optional weekly-digest polish pass.
class DigestPolishState {
  const DigestPolishState({
    this.title,
    this.body,
    this.loading = false,
    this.error,
    this.flagged = false,
  });
  final String? title;
  final String? body;
  final bool loading;
  final String? error;

  /// Whether the on-device gatekeeper flagged the polished digest (an invented
  /// label, leaked-looking PII, or an out-of-range figure). The text is still
  /// shown; the UI adds a "Checked on-device" note.
  final bool flagged;

  bool get isIdle => title == null && !loading && error == null;
  static const idle = DigestPolishState();
}

/// On-demand LLM polish for the weekly digest. Reuses the proven
/// anonymize → LLM → restore pipeline: the digest's top-category name is
/// replaced with an opaque label before it leaves the device, the LLM
/// rewrites a single {title, body} summary, and labels are restored on-device.
/// Falls back to the deterministic digest text when AI is off / no key / any
/// failure. Privacy unchanged: notes, contact names/phones/photos never enter
/// this path.
class WeeklyDigestPolishController extends StateNotifier<DigestPolishState> {
  WeeklyDigestPolishController(this._ref) : super(DigestPolishState.idle);
  final Ref _ref;

  Future<void> polish() async {
    if (state.loading) return;
    // Defense-in-depth: the AI summary card is hidden unless AI is effectively
    // enabled, but refuse here too so no outbound LLM call can fire in Offline
    // mode (or with AI off) — even if some future caller invokes polish().
    if (!_ref.read(aiEffectiveEnabledProvider)) {
      return;
    }
    state = const DigestPolishState(loading: true);
    try {
      final digest = await _ref.read(weeklyDigestProvider.future);
      final config = await aiConfigWithKey(_ref);
      if (config == null) {
        state = const DigestPolishState(error: 'Add your AI API key in Settings.');
        return;
      }

      final vocab = await _buildVocabulary(digest);
      final anonymizer = InsightAnonymizer(
        categories: vocab.categories,
        modes: vocab.modes,
      );

      // Build a single (title, body) representation and anonymize names.
      final plain = (
        title: 'Weekly digest: ${_fmt(digest.spentThisWeek)} spent this week',
        body: _plainBody(digest),
      );
      final anon = anonymizer.anonymizeInsights([
        AiInsight(title: plain.title, body: plain.body),
      ]).first;

      final userMessage = jsonEncode({'title': anon.title, 'body': anon.body});
      final client = _ref.read(aiClientProvider);
      final reply = await client.complete(
        config,
        [
          const ChatMessage(role: 'system', content: kDigestPolishSystemPrompt),
          ChatMessage(
            role: 'user',
            content: 'Rewrite this weekly digest as a friendly 2-sentence '
                'summary. Return ONLY a JSON object {"title","body"}:\n$userMessage',
          ),
        ],
        maxTokens: 400,
      );

      final decoded = jsonDecode(reply.trim());
      if (decoded is! Map ||
          decoded['title'] is! String ||
          decoded['body'] is! String) {
        throw const FormatException('Expected a {title, body} object');
      }

      // Route the polished digest through the on-device gatekeeper (built from
      // the InsightAnonymizer legend + the figures in the local digest) so it
      // is restored AND checked — PII-scrub + numeric sanity now apply to the
      // digest polish path, mirroring chat/report. Names were never sent
      // (always anonymized), so sentNameVocabulary is null.
      final sentAmounts = _amountsFromText(['${plain.title} ${plain.body}']);
      final maxAmount = sentAmounts.fold<double>(0.0, max);
      final gatekeeper = AiGatekeeper(
        legend: anonymizer.labelToName,
        validLabels: anonymizer.labelToName.keys.toSet(),
        maxContextAmount: maxAmount > 0 ? maxAmount : null,
        sentAmounts: sentAmounts,
      );
      final title = gatekeeper.restore(decoded['title'] as String);
      final body = gatekeeper.restore(decoded['body'] as String);
      final check = gatekeeper.check('$title $body');
      if (check.severity == AiCheckSeverity.bad) {
        state = DigestPolishState(error: check.issues.join(' '));
        return;
      }
      state = DigestPolishState(
        title: title,
        body: body,
        flagged: check.severity == AiCheckSeverity.flagged,
      );
    } on LlmException catch (e) {
      state = DigestPolishState(error: e.userMessage);
    } catch (e) {
      state = DigestPolishState(error: 'Could not polish digest: $e');
    }
  }

  /// Pull every numeric figure out of the supplied text — these are the
  /// amounts the LLM saw (anonymization changes names, not numbers) — so the
  /// gatekeeper can flag any polished figure that matches nothing sent.
  Set<double> _amountsFromText(Iterable<String> texts) {
    final amounts = <double>{};
    final re = RegExp(r'\d[\d,]*(?:\.\d+)?');
    for (final t in texts) {
      for (final m in re.allMatches(t)) {
        final n = double.tryParse(m.group(0)!.replaceAll(',', ''));
        if (n != null) amounts.add(n);
      }
    }
    return amounts;
  }

  void reset() => state = DigestPolishState.idle;

  String _plainBody(WeeklyDigest d) {
    final parts = <String>[];
    if (d.hasPriorWeek && d.deltaPct.isFinite) {
      parts.add('change vs last week: ${d.deltaPct.toStringAsFixed(0)}%');
    }
    if (d.topCategoryName != null) {
      parts.add('top category: ${d.topCategoryName} '
          '(${_fmt(d.topCategoryAmount)})');
    }
    parts.add('transactions this week: ${d.txnCountThisWeek}');
    if (d.observations.isNotEmpty) parts.add(d.observations.first);
    return parts.join('; ');
  }

  String _fmt(double n) => n.toStringAsFixed(0);

  /// Vocabulary = the digest's top category + every category/mode name from
  /// the last 14 days of expenses (the digest window).
  Future<({Set<String> categories, Set<String> modes})> _buildVocabulary(
      WeeklyDigest d) async {
    final repo = _ref.read(reportsRepositoryProvider);
    final from = d.weekStart.subtract(const Duration(days: 7)).toIso8601String();
    final to = d.weekEnd.add(const Duration(seconds: 1)).toIso8601String();
    final rows = await repo.transactionsForExport(from: from, to: to);
    final categories = <String>{};
    final modes = <String>{};
    for (final r in rows) {
      if (r.categoryName.trim().isNotEmpty) categories.add(r.categoryName);
      if (r.modeName.trim().isNotEmpty) modes.add(r.modeName);
    }
    if (d.topCategoryName != null && d.topCategoryName!.isNotEmpty) {
      categories.add(d.topCategoryName!);
    }
    return (categories: categories, modes: modes);
  }
}