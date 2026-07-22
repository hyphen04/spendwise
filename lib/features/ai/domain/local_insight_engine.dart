import 'dart:math';

import '../../../data/models/report_models.dart';

/// Severity tone carried on an [AiInsight]. Retained as the shared type behind
/// the on-device anonymize → LLM → restore pipeline used by the weekly digest.
enum InsightSeverity { positive, info, warning }

/// A single locally-computed insight: a {title, body} pair with a severity and
/// optional emoji. This is a no-API-key, on-device value object — pure data, no
/// network. The optional LLM polish pass for the weekly digest consumes one of
/// these as already-anonymized text, so it never needs fresh access to user
/// data.
class AiInsight {
  const AiInsight({
    required this.title,
    required this.body,
    this.severity = InsightSeverity.info,
    this.emoji,
  });

  final String title;
  final String body;
  final InsightSeverity severity;
  final String? emoji;

  String get oneLine => '$title — $body';
}

/// Structured recurring-payment detection result (see [LocalInsightEngine.detectRecurring]).
/// The Bills feature uses these to seed `recurring_items` rows on-device.
class DetectedRecurring {
  const DetectedRecurring({
    required this.categoryName,
    required this.modeName,
    required this.amount,
    required this.cadence,
    required this.occurrences,
    required this.lastDate,
  });
  final String categoryName;
  final String modeName;
  final double amount;
  final String
      cadence; // weekly|fortnightly|monthly|quarterly|yearly|'every N days'
  final int occurrences;
  final String lastDate; // ISO date of the most recent matching transaction
}

/// Deterministic, on-device detectors.
///
/// [detectRecurring] is a pure function over [ExportRow]s — no network, no API
/// key. Privacy note: recurring-payment detection reads [ExportRow]s locally,
/// which include a `note` field; that's fine because nothing leaves the device.
/// The Bills feature resolves the returned [DetectedRecurring] category/mode
/// names to ids on-device and seeds `recurring_items` rows.
class LocalInsightEngine {
  LocalInsightEngine._();

  // ── Recurring-payment detection ─────────────────────────────────────────
  //
  // Groups expenses by (category, payment mode) and looks for repeated
  // near-equal amounts at a consistent interval — the signature of a
  // subscription or recurring bill. Uses a low coefficient-of-variation
  // threshold on the amounts and a consistent day-gap, with a minimum count of
  // 3 occurrences so a one-off coincidence can't trigger it.

  static const int _recurringMinOccurrences = 3;
  static const double _recurringAmountCv = 0.05; // amounts within ~5% of mean

  /// Structured result of recurring-payment detection. The Bills feature seeds
  /// `recurring_items` rows from this (resolving `categoryName` → categoryId on
  /// the device). `cadence` is one of weekly/fortnightly/monthly/quarterly/yearly
  /// or "every N days" (irregular but consistent).
  static List<DetectedRecurring> detectRecurring(List<ExportRow> expenses) {
    final byGroup = <String, List<ExportRow>>{};
    for (final e in expenses) {
      if (e.amount <= 0) continue;
      final key = '${e.categoryName}::${e.modeName}';
      byGroup.putIfAbsent(key, () => []).add(e);
    }

    final results = <DetectedRecurring>[];
    for (final entry in byGroup.entries) {
      final rows = entry.value;
      if (rows.length < _recurringMinOccurrences) continue;

      rows.sort((a, b) => a.date.compareTo(b.date));

      final amounts = rows.map((r) => r.amount).toList();
      final mean = amounts.reduce((a, b) => a + b) / amounts.length;
      final variance =
          amounts.map((a) => (a - mean) * (a - mean)).reduce((a, b) => a + b) /
              amounts.length;
      final std = variance <= 0 ? 0.0 : sqrt(variance);
      final cv = mean > 0 ? std / mean : 1.0;
      if (cv > _recurringAmountCv) continue;

      final dates = rows
          .map((r) => DateTime.tryParse(r.date))
          .whereType<DateTime>()
          .toList();
      if (dates.length < _recurringMinOccurrences) continue;
      final gaps = <int>[];
      for (int i = 1; i < dates.length; i++) {
        gaps.add(dates[i].difference(dates[i - 1]).inDays.abs());
      }
      final meanGap = gaps.reduce((a, b) => a + b) / gaps.length;
      if (meanGap <= 0) continue;
      final gapSpread =
          gaps.map((g) => (g - meanGap).abs()).reduce((a, b) => a + b) /
              gaps.length;
      if (gapSpread / meanGap > 0.25) continue; // too irregular

      final parts = entry.key.split('::');
      final categoryName = parts.first;
      final modeName = parts.length > 1 ? parts[1] : '';
      results.add(DetectedRecurring(
        categoryName: categoryName,
        modeName: modeName,
        amount: mean,
        cadence: _cadenceLabel(meanGap),
        occurrences: rows.length,
        lastDate: rows.last.date,
      ));
    }
    return results;
  }

  static String _cadenceLabel(double meanGapDays) {
    if (meanGapDays >= 27 && meanGapDays <= 33) return 'monthly';
    if (meanGapDays >= 6 && meanGapDays <= 8) return 'weekly';
    if (meanGapDays >= 13 && meanGapDays <= 16) return 'fortnightly';
    if (meanGapDays >= 85 && meanGapDays <= 95) return 'quarterly';
    if (meanGapDays >= 360 && meanGapDays <= 370) return 'yearly';
    return 'every ${meanGapDays.round()} days';
  }
}
