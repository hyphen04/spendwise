import '../../data/repositories/reports_repository.dart';

/// A no-shame weekly digest, computed entirely on-device.
///
/// Summarizes the current week (Mon–Sun) vs last week: total spent, the
/// change, the top category this week, and a single observation/tip. No
/// network required for the core — the optional LLM polish pass
/// (`WeeklyDigestPolishController`) reuses the existing anonymize→LLM→restore
/// pipeline and only runs when AI is on + a key is set.
class WeeklyDigest {
  const WeeklyDigest({
    required this.weekStart,
    required this.weekEnd,
    required this.spentThisWeek,
    required this.spentLastWeek,
    required this.deltaPct,
    required this.txnCountThisWeek,
    required this.txnCountLastWeek,
    required this.topCategoryName,
    required this.topCategoryAmount,
    required this.observations,
    required this.tip,
  });

  final DateTime weekStart; // Monday 00:00
  final DateTime weekEnd; // Sunday 23:59:59
  final double spentThisWeek;
  final double spentLastWeek;
  final double deltaPct; // (this - last) / last, negative if down. NaN if no prior.
  final int txnCountThisWeek;
  final int txnCountLastWeek; // 0 ⇒ no prior-week data to compare against
  final String? topCategoryName;
  final double topCategoryAmount;
  final List<String> observations; // 1-3 short, observational bullets
  final String tip; // one no-shame nudge

  /// Whether there was any prior-week activity to compare against. Distinct
  /// from `spentLastWeek > 0` — a £0-spend week with transactions is still a
  /// valid comparison baseline.
  bool get hasPriorWeek => txnCountLastWeek > 0;

  /// Plain-text, shareable rendering (user owns their summary).
  String toShareText() {
    final buf = StringBuffer('SpendWise — weekly digest\n');
    buf.writeln('${_fmtDate(weekStart)} – ${_fmtDate(weekEnd)}');
    buf.writeln();
    buf.writeln('This week: ₹${_fmt(spentThisWeek)} '
        'across $txnCountThisWeek ${txnCountThisWeek == 1 ? 'transaction' : 'transactions'}.');
    if (hasPriorWeek) {
      final dir = deltaPct < 0 ? 'down' : 'up';
      buf.writeln(
          'Last week: ₹${_fmt(spentLastWeek)} ($dir ${(deltaPct.abs() * 100).toStringAsFixed(0)}%).');
    } else {
      buf.writeln('Last week: no spending recorded.');
    }
    if (topCategoryName != null) {
      buf.writeln('Top category: $topCategoryName '
          '(₹${_fmt(topCategoryAmount)}).');
    }
    for (final o in observations) {
      buf.writeln('• $o');
    }
    buf.writeln();
    buf.writeln('Tip: $tip');
    return buf.toString();
  }
}

class WeeklyDigestService {
  WeeklyDigestService(this._reports);
  final ReportsRepository _reports;

  /// Compute the digest for the week containing [now] (default: now). Pure
  /// on-device aggregation over the last ~14 days of expenses.
  Future<WeeklyDigest> compute({DateTime? now}) async {
    final today = DateTime.now();
    final n = now ?? today;

    // Monday as the start of the week (ISO). DateTime.weekday: Mon=1..Sun=7.
    final thisWeekStart =
        DateTime(n.year, n.month, n.day).subtract(Duration(days: n.weekday - 1));
    final thisWeekEnd =
        thisWeekStart.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));

    final fromIso = lastWeekStart.toIso8601String();
    final toIso = thisWeekEnd.add(const Duration(seconds: 1)).toIso8601String();

    final rows = await _reports.transactionsForExport(
      from: fromIso,
      to: toIso,
      kind: 'expense',
    );

    double spentThisWeek = 0, spentLastWeek = 0;
    int txnCountThisWeek = 0;
    int txnCountLastWeek = 0;
    final byCatThisWeek = <String, double>{};

    for (final r in rows) {
      final d = DateTime.tryParse(r.date);
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      final isThisWeek =
          !day.isBefore(thisWeekStart) && !day.isAfter(thisWeekEnd);
      final isLastWeek =
          !day.isBefore(lastWeekStart) && day.isBefore(thisWeekStart);

      if (isThisWeek) {
        spentThisWeek += r.amount;
        txnCountThisWeek++;
        byCatThisWeek[r.categoryName] =
            (byCatThisWeek[r.categoryName] ?? 0) + r.amount;
      } else if (isLastWeek) {
        spentLastWeek += r.amount;
        txnCountLastWeek++;
      }
    }

    String? topCat;
    double topAmt = 0;
    for (final e in byCatThisWeek.entries) {
      if (e.value > topAmt) {
        topAmt = e.value;
        topCat = e.key;
      }
    }

    final hasPrior = txnCountLastWeek > 0;
    final double deltaPct;
    if (!hasPrior) {
      deltaPct = double.nan;
    } else if (spentLastWeek == 0) {
      // Prior-week data exists but totaled £0 (e.g. only £0 entries). Going to
      // any positive spend is a +100% rise; staying at £0 is flat.
      deltaPct = spentThisWeek > 0 ? 1.0 : 0.0;
    } else {
      deltaPct = (spentThisWeek - spentLastWeek) / spentLastWeek;
    }

    final observations = <String>[];
    if (hasPrior) {
      if (deltaPct <= -0.10) {
        observations.add(
            'Spending is down ${(deltaPct.abs() * 100).toStringAsFixed(0)}% vs last week.');
      } else if (deltaPct >= 0.20) {
        observations.add(
            'Spending is up ${(deltaPct * 100).toStringAsFixed(0)}% vs last week.');
      } else {
        observations.add('Spending is close to last week.');
      }
    } else if (spentThisWeek == 0) {
      observations.add('No expenses logged this week yet.');
    }
    if (topCat != null) {
      final share = spentThisWeek > 0 ? (topAmt / spentThisWeek * 100) : 0.0;
      observations.add(
          '$topCat made up ${share.toStringAsFixed(0)}% of this week\'s spend.');
    }

    final tip = _tip(spentThisWeek, spentLastWeek, byCatThisWeek);

    return WeeklyDigest(
      weekStart: thisWeekStart,
      weekEnd: thisWeekEnd,
      spentThisWeek: spentThisWeek,
      spentLastWeek: spentLastWeek,
      deltaPct: deltaPct,
      txnCountThisWeek: txnCountThisWeek,
      txnCountLastWeek: txnCountLastWeek,
      topCategoryName: topCat,
      topCategoryAmount: topAmt,
      observations: observations,
      tip: tip,
    );
  }

  String _tip(double thisWeek, double lastWeek, Map<String, double> byCat) {
    if (thisWeek == 0 && lastWeek == 0) {
      return 'Log a transaction to start seeing your week take shape.';
    }
    if (lastWeek > 0 && thisWeek > lastWeek * 1.2) {
      final top = byCat.entries.fold<MapEntry<String, double>?>(
          null, (a, e) => (a == null || e.value > a.value) ? e : a);
      if (top != null) {
        return 'Most of the lift came from ${top.key}. Worth a quick look '
            'before next week — no need to cut, just notice.';
      }
      return 'A bit more than last week. A 10-second scan of the biggest '
          'category can help next week go smoother.';
    }
    if (lastWeek > 0 && thisWeek < lastWeek * 0.9) {
      return 'Lighter week than last. Nice — maybe move a little to a goal?';
    }
    return 'Steady week. If a goal is open, a small contribution keeps it moving.';
  }
}

String _fmt(double n) => n.toStringAsFixed(2);

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} '
    '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';