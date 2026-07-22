import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';
import '../data/models/budget_progress.dart';
import '../data/models/home_summary.dart';
import '../data/models/transaction_row.dart';
import '../data/repositories/budgets_repository.dart';
import 'database_provider.dart';
import 'manage_providers.dart';
import 'transactions_providers.dart';

final budgetsRepositoryProvider = Provider<BudgetsRepository>((ref) =>
    BudgetsRepository(ref.watch(appDatabaseProvider)));

/// Date of the oldest transaction — used to disable the back arrow in MonthNav.
final earliestTransactionDateProvider = FutureProvider<DateTime?>(
  (ref) {
    ref.watch(allTransactionsStreamProvider);
    return ref
        .watch(appDatabaseProvider)
        .transactionsDao
        .earliestTransactionDate();
  },
);

final budgetsStreamProvider = StreamProvider<List<Budget>>((ref) =>
    ref.watch(budgetsRepositoryProvider).watchAll());

/// Global absolute net worth across all time.
final globalNetWorthProvider = Provider<AsyncValue<double>>((ref) {
  final txAsync = ref.watch(allTransactionsStreamProvider);
  final accAsync = ref.watch(accountsStreamProvider);

  if (txAsync is AsyncLoading || accAsync is AsyncLoading) {
    return const AsyncLoading();
  }

  if (txAsync.hasError) return AsyncError(txAsync.error!, txAsync.stackTrace!);
  if (accAsync.hasError) return AsyncError(accAsync.error!, accAsync.stackTrace!);

  double total = 0;
  for (final acc in accAsync.valueOrNull ?? <Account>[]) {
    if (!acc.isArchived) total += acc.openingBalance;
  }
  for (final tx in txAsync.valueOrNull ?? <Transaction>[]) {
    // Only sum transactions belonging to unarchived accounts
    final accMap = {for (final a in accAsync.valueOrNull ?? <Account>[]) a.id: a};
    final acc = accMap[tx.accountId];
    if (acc != null && !acc.isArchived) {
      if (tx.kind == 'income' || tx.kind == 'transfer_in') {
        total += tx.amount;
      } else if (tx.kind == 'expense' || tx.kind == 'transfer_out') {
        total -= tx.amount;
      }
    }
  }

  return AsyncData(total);
});

/// Income + expense totals for a given (year, month).
final homeSummaryProvider =
    Provider.family<HomeSummary, (int, int)>((ref, args) {
  final txAsync = ref.watch(transactionsByMonthProvider(args));
  return txAsync.when(
    data: (txs) {
      double income = 0, expense = 0;
      for (final tx in txs) {
        if (tx.kind == 'income') {
          income += tx.amount;
        } else if (tx.kind == 'expense') {
          expense += tx.amount;
        }
      }
      return HomeSummary(income: income, expense: expense);
    },
    loading: () => const HomeSummary.zero(),
    error: (_, __) => const HomeSummary.zero(),
  );
});

/// Budget progress for a given month — loaded once (FutureProvider).
final budgetProgressProvider =
    FutureProvider.family<List<BudgetProgress>, (int, int)>((ref, args) {
  final month = DateTime(args.$1, args.$2);
  // Invalidate when budgets or transactions change
  ref.watch(budgetsStreamProvider);
  ref.watch(transactionsByMonthProvider(args));
  return ref.read(budgetsRepositoryProvider).progressForMonth(month);
});

/// TransactionRows for a given (year, month), enriched with names.
/// Sorted newest-first — mirrors the DAO's DESC order.
final monthTransactionRowsProvider =
    Provider.family<List<TransactionRow>, (int, int)>((ref, args) {
  final accAsync = ref.watch(accountsStreamProvider);
  final catAsync = ref.watch(categoriesStreamProvider);
  final modeAsync = ref.watch(modesStreamProvider);
  final txAsync = ref.watch(transactionsByMonthProvider(args));

  final txs = txAsync.valueOrNull ?? [];
  final accMap = {
    for (final a in accAsync.valueOrNull ?? <Account>[]) a.id: a
  };
  final catMap = {
    for (final c in catAsync.valueOrNull ?? <Category>[]) c.id: c
  };
  final modeMap = {
    for (final m in modeAsync.valueOrNull ?? <Mode>[]) m.id: m
  };

  return txs
      .where((tx) => tx.kind != 'transfer_in')
      .map((tx) {
        Account? pairAccount;
        if (tx.kind.startsWith('transfer') && tx.transferPairId != null) {
          final pairTx = txs.where((t) => t.id == tx.transferPairId).firstOrNull;
          if (pairTx != null) {
            pairAccount = accMap[pairTx.accountId];
          }
        }
        return TransactionRow(
          transaction: tx,
          account: accMap[tx.accountId],
          category: catMap[tx.categoryId],
          mode: modeMap[tx.modeId],
          transferPairAccount: pairAccount,
        );
      })
      .toList();
});

/// Top expense categories for a given (year, month) — drives the Home
/// "where it went" card. Derived on-device from [monthTransactionRowsProvider]
/// (expense rows only, grouped by category, summed, sorted desc, top 4).
/// No SQL/DAO change. Each entry pairs the resolved [Category] (for icon/name/
/// color) with its spend amount. Empty when the month has no expenses.
final monthTopCategoriesProvider =
    Provider.family<List<({Category cat, double amount})>, (int, int)>((ref, args) {
  final rows = ref.watch(monthTransactionRowsProvider(args));
  final sums = <String, double>{};
  for (final r in rows) {
    if (r.transaction.kind != 'expense') continue;
    final cid = r.transaction.categoryId;
    sums[cid] = (sums[cid] ?? 0) + r.transaction.amount;
  }
  final entries = sums.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final cats = {
    for (final c in ref.watch(categoriesStreamProvider).valueOrNull ?? <Category>[])
      c.id: c,
  };
  return entries.take(4).map((e) {
    final c = cats[e.key];
    if (c == null) return null;
    return (cat: c, amount: e.value);
  }).whereType<({Category cat, double amount})>().toList();
});

/// Aggregate budget progress for a given (year, month) — drives the Home spent
/// hero's single progress bar. Sums `spent` and `effectiveAmount` across every
/// [BudgetProgress] from [budgetProgressProvider]. `hasBudgets` is false when
/// there are no budgets (the hero then hides the bar). `fraction` is clamped to
/// [0,1]; `isOver` flags the over-budget red state.
final overallBudgetProgressProvider =
    Provider.family<({double spent, double budget, double fraction, bool hasBudgets, bool isOver}), (int, int)>(
        (ref, args) {
  final all = ref.watch(budgetProgressProvider(args)).valueOrNull ?? <BudgetProgress>[];
  double spent = 0, budget = 0;
  for (final b in all) {
    spent += b.spent;
    budget += b.effectiveAmount;
  }
  final hasBudgets = budget > 0;
  final raw = hasBudgets ? spent / budget : 0.0;
  return (
    spent: spent,
    budget: budget,
    fraction: raw.clamp(0.0, 1.0),
    hasBudgets: hasBudgets,
    isOver: spent > budget,
  );
});

