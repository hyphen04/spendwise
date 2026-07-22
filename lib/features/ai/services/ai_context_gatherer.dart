import '../../../data/db/app_database.dart';
import '../../../data/models/report_models.dart';
import '../../../data/repositories/goals_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../data/repositories/reports_repository.dart';
import '../domain/ai_mention_resolver.dart';
import '../domain/ai_payload_builder.dart';

/// The anonymized-aggregate extras that extend the AI outbound payload beyond
/// the original summary/budgets/cashflow set. Gathered once per context build
/// and passed to [AiPayloadBuilder.buildAskContext] / [buildReportContext].
/// All names are labelized on-device by the builder; only opaque ids + figures
/// leave the device.
typedef AiContextExtras = ({
  List<AccountBalance> accountBalances,
  List<List<CategoryTotal>> categoryBreakdown3mo,
  int? expenseCount,
  int? daysInPeriod,
  Map<String, double> dailyExpenseByDay,
  List<GoalSummary> goals,
  List<BillSummary> recurringBills,
});

/// Gather the extended anonymized aggregates for an AI context build, for the
/// month `(year, month)`. Reads only safe tables (accounts, transactions,
/// categories, modes, goals, recurring_items) — never `due_*` / `ai_*`,
/// never `note` / `receipt_path` / contact columns. Goal and bill names are
/// passed to the builder solely so the on-device legend can map `goal_N` /
/// `bill_N` back to real names; they never appear in the outbound JSON unless
/// `shareNames` is on (gated in the builder).
///
/// `categoryBreakdown3mo` is returned oldest→newest (3 entries) so the builder
/// can emit `category_trend_3mo` for the top categories. `daysInPeriod` is the
/// day-of-month for the current month (month-to-date average) or the full
/// month length for a past month.
Future<AiContextExtras> gatherAiContextExtras({
  required ReportsRepository reports,
  required GoalsRepository goalsRepo,
  required RecurringRepository recurringRepo,
  required int year,
  required int month,
}) async {
  final monthDate = DateTime(year, month);
  final from = monthDate.toIso8601String();
  final to = DateTime(year, month + 1).toIso8601String();

  final accountBalances = await reports.accountBalances();
  final dailyExpenseByDay =
      await reports.dailyExpenseByDay(from: from, to: to);
  final expenseCount =
      await reports.expenseCountInRange(from: from, to: to);
  final now = DateTime.now();
  final daysInPeriod = (now.year == year && now.month == month)
      ? now.day
      : DateTime(year, month + 1, 0).day;

  // Last 3 months of expense category breakdown (oldest → newest).
  final categoryBreakdown3mo = <List<CategoryTotal>>[];
  for (int i = 2; i >= 0; i--) {
    final p = DateTime(year, month - i); // Dart normalizes month underflow.
    final pf = DateTime(p.year, p.month).toIso8601String();
    final pt = DateTime(p.year, p.month + 1).toIso8601String();
    categoryBreakdown3mo
        .add(await reports.categoryBreakdown(from: pf, to: pt, kind: 'expense'));
  }

  // Goals — anonymized aggregates only (no name/icon/note in outbound JSON).
  final allGoals = await goalsRepo.getAll();
  final goals = <GoalSummary>[];
  for (final g in allGoals.where((g) => g.isActive)) {
    final p = goalsRepo.progressFor(g);
    goals.add((
      id: g.id,
      name: g.name,
      target: p.target,
      saved: p.saved,
      monthsLeft: p.monthsLeft,
      monthlyCommitment: g.monthlyCommitment,
    ));
  }

  // Recurring bills — anonymized aggregates only (no name/note in outbound).
  final allBills = await recurringRepo.getAll();
  final bills = <BillSummary>[];
  for (final b in allBills.where((b) => b.isActive)) {
    bills.add((
      id: b.id,
      name: b.name,
      amount: b.amount,
      cadence: b.cadence,
      nextDueInDays: recurringRepo.daysUntilDue(b),
      source: b.source,
    ));
  }

  return (
    accountBalances: accountBalances,
    categoryBreakdown3mo: categoryBreakdown3mo,
    expenseCount: expenseCount,
    daysInPeriod: daysInPeriod,
    dailyExpenseByDay: dailyExpenseByDay,
    goals: goals,
    recurringBills: bills,
  );
}

/// Gather the **on-device-only** entity directory + current-month figures used
/// by [AiMentionResolver] to bridge the user's real-name mentions to the
/// anonymized labels/amounts the LLM holds.
///
/// **Privacy contract — this is never sent to the LLM wholesale.** The
/// directory (every active category/account/mode name) stays on-device.
/// Only names the user *themselves typed* in their own message can appear in a
/// resolver hint, and only because the user already put them in the outbound
/// text — the legend for unmentioned entities never leaves. The amount maps are
/// the same aggregates the payload already sends (so no new figures are
/// exposed). Reads only the safe tables (categories/accounts/modes) and the
/// already-gathered [AiContextExtras] + mode breakdown — never `due_*` / `ai_*`,
/// never `note` / `receipt_path` / contact columns.
///
/// `modeBreakdown` is the current-month expense mode breakdown (already fetched
/// by the chat controller) — reused here instead of re-querying.
Future<AiMentionData> gatherAiMentionData({
  required AppDatabase db,
  required List<ModeTotal> modeBreakdown,
  required AiContextExtras extras,
}) async {
  final cats = await db.categoriesDao.getAllActive();
  final modes = await db.modesDao.getAllActive();

  // Current-month category spend: the last entry of the 3-month series is the
  // current month. Categories with no spend are simply absent (amount 0).
  final categoryAmount = <String, double>{};
  if (extras.categoryBreakdown3mo.length == 3) {
    for (final c in extras.categoryBreakdown3mo[2]) {
      categoryAmount[c.categoryId] = c.total;
    }
  }
  final modeAmount = {for (final m in modeBreakdown) m.modeId: m.total};
  final accountBalance = {
    for (final a in extras.accountBalances) a.id: a.balance,
  };

  return AiMentionData(
    categories: cats.map((c) => (id: c.id, name: c.name)).toList(),
    accounts: extras.accountBalances
        .map((a) => (id: a.id, name: a.name))
        .toList(),
    modes: modes.map((m) => (id: m.id, name: m.name)).toList(),
    categoryAmount: categoryAmount,
    modeAmount: modeAmount,
    accountBalance: accountBalance,
  );
}