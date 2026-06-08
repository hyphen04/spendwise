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
      if (tx.kind == 'income') {
        total += tx.amount;
      } else if (tx.kind == 'expense') {
        total -= tx.amount;
      }
    }
  }

  return AsyncData(total);
});

/// Latest 10 transactions across all time.
final globalRecentTransactionsProvider = Provider<List<TransactionRow>>((ref) {
  return (ref.watch(transactionRowsProvider).valueOrNull ?? []).take(10).toList();
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
      .map((tx) => TransactionRow(
            transaction: tx,
            account: accMap[tx.accountId],
            category: catMap[tx.categoryId],
            mode: modeMap[tx.modeId],
          ))
      .toList();
});

