import 'dart:math';

import '../../../app/utils/money_format.dart';
import '../../../data/models/budget_progress.dart';
import '../../../data/models/report_models.dart';

/// Severity of a generated insight, used by [AiInsightCard] for color tone.
enum InsightSeverity { positive, info, warning }

/// A single locally-computed insight. This is the no-API-key path: pure
/// functions over the app's own pre-computed aggregations, evaluated on-device.
///
/// These are *not* AI output. They run for every user, offline, with no key —
/// they're the free hook that demonstrates value before the opt-in AI layer.
/// The optional LLM "polish" pass (Phase 5) consumes these same objects as
/// already-anonymized text, so it never needs fresh access to user data.
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
  final String cadence; // weekly|fortnightly|monthly|quarterly|yearly|'every N days'
  final int occurrences;
  final String lastDate; // ISO date of the most recent matching transaction
}

/// Deterministic, on-device insight detectors.
///
/// Every method is a pure function over existing aggregation models
/// ([BudgetProgress], [CategoryTotal], [MonthTotal], [ExportRow]) — no network,
/// no API key, no raw-row access beyond the export shape. Privacy note:
/// recurring-payment detection reads [ExportRow]s locally, which include a
/// `note` field; that's fine because nothing leaves the device. When these
/// insights are later sent to the LLM for polishing (Phase 5), only the
/// generated [AiInsight] text is forwarded — never the export rows.
class LocalInsightEngine {
  LocalInsightEngine._();

  // ── Budget trajectory projection ─────────────────────────────────────────
  //
  // Projects the month-end spend from the current daily run-rate and warns
  // when a category is on track to exceed its budget. Only projects after day
  // 5 of the month — earlier than that the run-rate is too noisy (a single
  // rent payment on the 1st would project 30× monthly spend).

  static const int _minDayToProject = 5;

  static List<AiInsight> budgetTrajectory(
    List<BudgetProgress> budgets,
    DateTime now,
  ) {
    if (now.day < _minDayToProject) return const [];

    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysElapsed = now.day; // today counts as elapsed
    final results = <AiInsight>[];

    for (final b in budgets) {
      final effective = b.effectiveAmount;
      if (effective <= 0) continue;

      // Already over budget — report the breach directly.
      if (b.isOver) {
        results.add(AiInsight(
          emoji: b.categoryIcon,
          severity: InsightSeverity.warning,
          title: '${b.categoryName} is over budget',
          body: 'You\'ve spent ${fmtMoney(b.spent)} against a '
              '${fmtMoney(effective)} budget — over by '
              '${fmtMoney(b.spent - effective)} with '
              '${daysInMonth - daysElapsed} days left this month.',
        ));
        continue;
      }

      final dailyRate = b.spent / daysElapsed;
      final projected = dailyRate * daysInMonth;
      if (projected <= effective) continue;

      // Solve dailyRate * d = effective for d → the day the budget is crossed.
      final crossDay = (effective / dailyRate).ceil().clamp(1, daysInMonth);
      results.add(AiInsight(
        emoji: b.categoryIcon,
        severity: InsightSeverity.warning,
        title: '${b.categoryName} on track to exceed budget',
        body: 'At your current pace you\'ll spend about '
            '${fmtMoney(projected)} — ${fmtMoney(projected - effective)} over '
            'the ${fmtMoney(effective)} budget. Projected to cross around the '
            '${dayOrdinal(crossDay)}.',
      ));
    }
    return results;
  }

  // ── Spending-spike anomaly ──────────────────────────────────────────────
  //
  // Flags a category whose current-month spend is well above its trailing
  // 3-month average. Uses two thresholds to avoid false positives on cheap
  // categories: a relative one (1.5× the average) AND an absolute floor on the
  // extra spend, so a ₹50→₹200 jump doesn't fire a scary warning.

  static const double _spikeRelativeThreshold = 1.5;
  static const double _spikeAbsoluteFloor = 500.0;
  static const double _newCategoryFloor = 1000.0;

  static List<AiInsight> spendingSpikes(
    List<CategoryTotal> current,
    List<List<CategoryTotal>> trailingMonths,
  ) {
    final results = <AiInsight>[];

    // Trailing average per category (only counts months in which the category
    // appeared, so a category that exists 2 of 3 months averages over 2).
    final sums = <String, double>{};
    final counts = <String, int>{};
    final names = <String, String>{};
    final icons = <String, String>{};
    for (final month in trailingMonths) {
      for (final c in month) {
        sums[c.categoryId] = (sums[c.categoryId] ?? 0) + c.total;
        counts[c.categoryId] = (counts[c.categoryId] ?? 0) + 1;
        names[c.categoryId] = c.name;
        icons[c.categoryId] = c.icon;
      }
    }

    for (final c in current) {
      if (c.total <= 0) continue;
      final avg = counts[c.categoryId] == null
          ? null
          : (sums[c.categoryId]! / counts[c.categoryId]!);

      if (avg == null || avg == 0) {
        // Genuinely new category this month.
        if (c.total >= _newCategoryFloor) {
          results.add(AiInsight(
            emoji: c.icon,
            severity: InsightSeverity.info,
            title: 'New spending: ${c.name}',
            body: 'You spent ${fmtMoney(c.total)} on ${c.name} this month — '
                'there was no spending here in the previous 3 months.',
          ));
        }
        continue;
      }

      if (c.total > avg * _spikeRelativeThreshold &&
          (c.total - avg) >= _spikeAbsoluteFloor) {
        final pct = ((c.total - avg) / avg * 100).round();
        results.add(AiInsight(
          emoji: c.icon,
          severity: InsightSeverity.warning,
          title: '${c.name} spending spiked',
          body: 'You spent ${fmtMoney(c.total)} on ${c.name} this month — '
              'up $pct% from your 3-month average of ${fmtMoney(avg)}.',
        ));
      }
    }
    return results;
  }

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

  static List<AiInsight> recurringPayments(List<ExportRow> expenses) =>
      detectRecurring(expenses).map((d) => AiInsight(
            emoji: '🔁',
            severity: InsightSeverity.info,
            title: 'Likely recurring charge in ${d.categoryName}',
            body: 'We spotted ${d.occurrences} near-equal payments of about '
                '${fmtMoney(d.amount)} (${d.cadence}) in ${d.categoryName}. '
                'Worth confirming it\'s still in use.',
          )).toList();

  static String _cadenceLabel(double meanGapDays) {
    if (meanGapDays >= 27 && meanGapDays <= 33) return 'monthly';
    if (meanGapDays >= 6 && meanGapDays <= 8) return 'weekly';
    if (meanGapDays >= 13 && meanGapDays <= 16) return 'fortnightly';
    if (meanGapDays >= 85 && meanGapDays <= 95) return 'quarterly';
    if (meanGapDays >= 360 && meanGapDays <= 370) return 'yearly';
    return 'every ${meanGapDays.round()} days';
  }

  // ── Savings-rate trend ───────────────────────────────────────────────────
  //
  // Looks at the last 6 months of income/expense and summarizes whether the
  // savings rate (net / income) is trending up, down, or is volatile. A
  // positive trend or high latest rate is celebrated; a falling trend is
  // flagged.

  static List<AiInsight> savingsTrend(List<MonthTotal> cashflow) {
    if (cashflow.length < 3) return const [];
    final results = <AiInsight>[];

    double rate(MonthTotal m) =>
        m.income > 0 ? (m.net / m.income) : 0.0;

    final rates = cashflow.map(rate).toList();
    final latest = rates.last;
    final prior = rates[rates.length - 2];

    // Simple linear trend over the full window (slope of least-squares fit).
    final n = rates.length.toDouble();
    final xs = List.generate(rates.length, (i) => i.toDouble());
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = rates.reduce((a, b) => a + b) / n;
    var num = 0.0, den = 0.0;
    for (int i = 0; i < rates.length; i++) {
      num += (xs[i] - meanX) * (rates[i] - meanY);
      den += (xs[i] - meanX) * (xs[i] - meanX);
    }
    final slope = den == 0 ? 0.0 : num / den;

    final last = cashflow.last;
    final monthLabel = _monthLabel(last);

    if (latest >= 0.2 && slope >= 0) {
      results.add(AiInsight(
        emoji: '📈',
        severity: InsightSeverity.positive,
        title: 'You\'re saving well',
        body: 'Your savings rate in $monthLabel was '
            '${(latest * 100).round()}% of income, and it\'s been trending up '
            'over the last ${cashflow.length} months.',
      ));
    } else if (slope < -0.03 && latest < prior) {
      results.add(AiInsight(
        emoji: '📉',
        severity: InsightSeverity.warning,
        title: 'Savings rate is slipping',
        body: 'Your savings rate in $monthLabel dropped to '
            '${(latest * 100).round()}% from ${(prior * 100).round()}% the '
            'month before. Expenses may be creeping up faster than income.',
      ));
    }
    return results;
  }

  static String _monthLabel(MonthTotal m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${names[m.month - 1]} ${m.year}';
  }
}