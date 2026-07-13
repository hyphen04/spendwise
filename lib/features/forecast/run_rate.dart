import '../../data/repositories/reports_repository.dart';
import '../../app/utils/tone.dart';

/// "You usually spend ~₹X on Fuel by now" — a no-shame run-rate observation
/// for a single category. [ratio] = actualThisMonth / typicalByNow (1.0 = on
/// your usual pace). Pure on-device aggregation; no network.
class RunRateObservation {
  const RunRateObservation({
    required this.categoryName,
    required this.icon,
    required this.color,
    required this.actual,
    required this.typical,
    required this.ratio,
  });

  final String categoryName;
  final String icon;
  final String color;
  final double actual; // spend this month (so far)
  final double typical; // avg spend up to today's day-of-month over trailing months
  final double ratio;

  String get label => Tone.runRateObservation(ratio);
}

class RunRateService {
  RunRateService(this._reports);
  final ReportsRepository _reports;

  /// Compute run-rate observations for the top [limit] categories, comparing
  /// this month's spend-so-far to the typical spend-by-now over the trailing
  /// [months] months. Categories with no trailing history are skipped (no
  /// baseline → no ratio).
  Future<List<RunRateObservation>> topObservations({
    int limit = 3,
    int months = 6,
    String? categoryIconColor, // unused; resolved by caller from cats stream
  }) async {
    final now = DateTime.now();
    final todayDay = now.day;
    final thisMonthKey = (now.year, now.month);
    final from = DateTime(now.year, now.month - (months - 1)).toIso8601String();
    final to = DateTime(now.year, now.month + 1).toIso8601String();

    final rows = await _reports.transactionsForExport(from: from, to: to, kind: 'expense');

    final actualThisMonth = <String, double>{};
    // Sum, per category, of spend up to today's day-of-month across trailing
    // (non-current) months.
    final trailingByNow = <String, double>{};
    int trailingMonths = 0;
    final seenMonths = <(int, int)>{};

    for (final r in rows) {
      final d = DateTime.tryParse(r.date);
      if (d == null) continue;
      final key = (d.year, d.month);
      final dom = d.day;
      if (key == thisMonthKey) {
        actualThisMonth[r.categoryName] =
            (actualThisMonth[r.categoryName] ?? 0) + r.amount;
      } else {
        if (dom <= todayDay) {
          trailingByNow[r.categoryName] =
              (trailingByNow[r.categoryName] ?? 0) + r.amount;
        }
        if (!seenMonths.contains(key)) {
          seenMonths.add(key);
          trailingMonths++;
        }
      }
    }

    if (trailingMonths == 0) return const [];

    final out = <RunRateObservation>[];
    for (final entry in actualThisMonth.entries) {
      final name = entry.key;
      final actual = entry.value;
      final trailing = trailingByNow[name] ?? 0;
      if (trailing <= 0) continue; // no baseline
      final typical = trailing / trailingMonths;
      if (typical <= 0) continue;
      final ratio = actual / typical;
      out.add(RunRateObservation(
        categoryName: name,
        icon: '📦',
        color: '#475569',
        actual: actual,
        typical: typical,
        ratio: ratio,
      ));
    }
    // Most over-pace first, but cap the "way under" tail too — show the
    // categories most worth a look.
    out.sort((a, b) => b.ratio.compareTo(a.ratio));
    return out.take(limit).toList();
  }
}