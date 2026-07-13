import '../../data/db/app_database.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../data/repositories/reports_repository.dart';
import '../../app/utils/tone.dart';

/// Which period the forecast surfaces (Home glance card + Forecast report)
/// are showing: the current month, or a rolling 6-month window.
enum ForecastMode { monthly, sixMonths }

/// A run-rate balance projection for a period, on-device. Observation tone,
/// no alarm.
///
/// **Monthly** extrapolates *spend only* to month-end (income is taken as-is,
/// so a salary landing mid-month isn't doubled) and counts only income already
/// logged. **6 months** takes the average monthly net over the last 6
/// completed months and projects it forward 6 months from today's balance —
/// "if your 6-month pace continues, where you'd be in 6 months". Both are
/// estimates, never targets.
class CashflowForecast {
  const CashflowForecast({
    required this.mode,
    required this.periodLabel,
    required this.openingBalance,
    required this.incomeSoFar,
    required this.expenseSoFar,
    required this.projectedIncome,
    required this.projectedExpense,
    required this.projectedEnd,
    required this.daysElapsed,
    required this.daysInPeriod,
    required this.billsDueBeforePeriodEnd,
    required this.outlook,
  });

  final ForecastMode mode;
  /// "July 2026" (monthly) or "next 6 months" (6-month).
  final String periodLabel;
  /// Monthly: balance at the start of the month. 6-month: current balance (now).
  final double openingBalance;
  final double incomeSoFar; // monthly: this month so far; 6-month: trailing 6mo total
  final double expenseSoFar; // monthly: this month so far; 6-month: trailing 6mo total
  /// Run-rate income for the period. Monthly: = incomeSoFar. 6-month: 6 × avg.
  final double projectedIncome;
  /// Run-rate spend for the period. Monthly: scaled to the month. 6-month: 6 × avg.
  final double projectedExpense;
  /// Monthly: opening + income − projectedExpense. 6-month: now + 6 × avgNet.
  final double projectedEnd;
  final int daysElapsed; // monthly: day of month; 6-month: 0 (not shown)
  final int daysInPeriod; // monthly: days in month; 6-month: 0
  final List<String> billsDueBeforePeriodEnd;
  final String outlook;

  bool get hasData =>
      mode == ForecastMode.sixMonths
          ? (incomeSoFar > 0 || expenseSoFar > 0 || openingBalance != 0)
          : (daysElapsed > 0 && (incomeSoFar > 0 || expenseSoFar > 0));

  /// Days remaining in the period (monthly only).
  int get daysLeft => daysInPeriod > 0
      ? (daysInPeriod - daysElapsed).clamp(0, daysInPeriod)
      : 0;
}

class CashflowForecastService {
  CashflowForecastService(this._reports, this._recurring);
  final ReportsRepository _reports;
  final RecurringRepository _recurring;

  /// Month-end projection (spend run-rated; income as-is).
  Future<CashflowForecast> computeMonthly({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final year = n.year;
    final month = n.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final daysElapsed = n.day.clamp(1, daysInMonth);

    final summary = await _reports.monthlySummary(year, month);
    final expense = summary.expense;
    final income = summary.income;
    final opening = summary.openingBalance;

    final projectedExpense = expense * daysInMonth / daysElapsed;
    final projectedEnd = opening + income - projectedExpense;

    final horizon = daysInMonth - n.day;
    final upcoming = horizon > 0
        ? await _recurring.dueInDays(horizon)
        : const <RecurringItem>[];
    final billsDue = upcoming.map((b) => b.name).toList();

    return CashflowForecast(
      mode: ForecastMode.monthly,
      periodLabel: '${_monthName(month)} $year',
      openingBalance: opening,
      incomeSoFar: income,
      expenseSoFar: expense,
      projectedIncome: income,
      projectedExpense: projectedExpense,
      projectedEnd: projectedEnd,
      daysElapsed: daysElapsed,
      daysInPeriod: daysInMonth,
      billsDueBeforePeriodEnd: billsDue,
      outlook: Tone.cashflowOutlook(projectedEnd, 0),
    );
  }

  /// 6-month-forward projection: today's balance + 6 × the average monthly net
  /// over the last 6 completed months. The trailing 6 months also feed the
  /// day-grid heatmap on the same screen.
  Future<CashflowForecast> computeSixMonths({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final year = n.year;

    // Last 7 months oldest→newest (current is last); take the 6 completed.
    final months = await _reports.cashFlowMonths(count: 7);
    final completed = months.take(6).toList();
    double sumIncome = 0, sumExpense = 0;
    for (final m in completed) {
      sumIncome += m.income;
      sumExpense += m.expense;
    }
    final avgIncome = completed.isNotEmpty ? sumIncome / completed.length : 0.0;
    final avgExpense = completed.isNotEmpty ? sumExpense / completed.length : 0.0;
    final avgNet = avgIncome - avgExpense;

    // Current balance (now).
    final balances = await _reports.yearlyBalances(year);
    final currentBalance = balances.$2;

    final projectedIncome = 6 * avgIncome;
    final projectedExpense = 6 * avgExpense;
    final projectedEnd = currentBalance + 6 * avgNet;

    // Known recurring bills due in the next ~6 months.
    const horizon = 183;
    final upcoming = await _recurring.dueInDays(horizon);
    final billsDue = upcoming.map((b) => b.name).toList();

    return CashflowForecast(
      mode: ForecastMode.sixMonths,
      periodLabel: 'next 6 months',
      openingBalance: currentBalance,
      incomeSoFar: sumIncome,
      expenseSoFar: sumExpense,
      projectedIncome: projectedIncome,
      projectedExpense: projectedExpense,
      projectedEnd: projectedEnd,
      daysElapsed: 0,
      daysInPeriod: 0,
      billsDueBeforePeriodEnd: billsDue,
      outlook: Tone.cashflowOutlook(projectedEnd, 0),
    );
  }

  static String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];
}