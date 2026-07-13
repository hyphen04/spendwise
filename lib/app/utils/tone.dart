/// No-shame tone helpers — observation, not alarm.
///
/// The research (Money Mirror, Track ThatMoney, Good With, Adjust 2025) is
/// consistent: red-as-failure cues, scores/grades, and alarmist copy raise
/// shame and *reduce* engagement with money tools. Status copy here frames
/// over-budget / behind-pace / overdue as a neutral heads-up ("a bit over",
/// "worth a look", "overdue by N days") — never "you failed".
///
/// Used by Bills (Phase 3), Goals (Phase 4), Weekly digest (Phase 5), and the
/// Cashflow forecast (Phase 6). Keep copy plain-language INR and observational.
class Tone {
  Tone._();

  /// Budget status copy. [fraction] is spent/target (0..1+, may exceed 1).
  static String budgetStatus(double fraction) {
    if (fraction <= 0.5) return 'On track';
    if (fraction <= 0.85) return 'Pacing well';
    if (fraction <= 1.0) return 'Nearly there';
    if (fraction <= 1.15) return 'A bit over';
    if (fraction <= 1.5) return 'Over budget';
    return 'Worth a look';
  }

  /// Savings-goal progress copy. [fraction] is saved/target (0..1+).
  static String goalStatus(double fraction, {int? monthsLeft}) {
    if (fraction >= 1.0) return 'Goal reached 🎉';
    if (fraction >= 0.75) return 'Almost there';
    if (fraction >= 0.25) return 'Building up';
    if (monthsLeft != null && monthsLeft <= 1) return 'Last stretch';
    return 'Just started';
  }

  /// Run-rate observation copy for a category: how actual spend so far this
  /// month compares to the typical pace by this day-of-month.
  /// [ratio] = actual / typical (1.0 = on pace).
  static String runRateObservation(double ratio) {
    if (ratio < 0.5) return 'Quieter than usual so far';
    if (ratio < 0.9) return 'Pacing under your usual';
    if (ratio <= 1.1) return 'About your usual pace';
    if (ratio <= 1.3) return 'A little ahead of usual';
    return 'Running higher than usual';
  }

  /// Cashflow projection copy for projected month-end balance vs a threshold.
  static String cashflowOutlook(double projectedEnd, double comfortFloor) {
    if (projectedEnd >= comfortFloor * 2) return 'Comfortable';
    if (projectedEnd >= comfortFloor) return 'Looking fine';
    if (projectedEnd > 0) return 'A bit tight by month-end';
    if (projectedEnd > -comfortFloor) return 'Worth a look before month-end';
    return 'Likely to dip below zero';
  }

  /// Bills due-due badge label (no-shame: overdue is a neutral heads-up).
  static String dueLabel(int dueDays) {
    if (dueDays < 0) return 'overdue by ${-dueDays}d';
    if (dueDays == 0) return 'due today';
    if (dueDays <= 3) return 'due in ${dueDays}d';
    return 'in ${dueDays}d';
  }

  /// Whether a due/projection state should use the warm-amber accent (true) or
  /// a neutral chip (false). Amber = "heads-up", never red = "failure".
  static bool isAmber(int dueDays) => dueDays <= 3;
}