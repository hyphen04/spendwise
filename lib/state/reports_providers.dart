import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';
import '../data/models/report_models.dart';
import '../data/repositories/reports_repository.dart';
import 'database_provider.dart';
import 'manage_providers.dart';
import 'transactions_providers.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
    (ref) => ReportsRepository(ref.watch(appDatabaseProvider)));

// (year, month) → MonthlySummary
final monthlySummaryProvider =
    FutureProvider.family<MonthlySummary, (int, int)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).monthlySummary(args.$1, args.$2);
});

// year → List<MonthTotal> for all 12 months
final monthlyTotalsProvider =
    FutureProvider.family<List<MonthTotal>, int>((ref, year) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).monthlyTotals(year);
});

// year → (opening balance, closing balance)
final yearlyBalancesProvider =
    FutureProvider.family<(double, double), int>((ref, year) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).yearlyBalances(year);
});

// (year, month) → List<DayTotal> for all days in the month
final dailyTotalsProvider =
    FutureProvider.family<List<DayTotal>, (int, int)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).dailyTotals(args.$1, args.$2);
});

// Rolling 6-month cash flow — re-evaluates whenever any transaction changes.
final cashFlowProvider = FutureProvider<List<MonthTotal>>((ref) {
  ref.watch(allTransactionsStreamProvider); // reactive: re-run on tx changes
  return ref.read(reportsRepositoryProvider).cashFlowMonths();
});

// (from, to) → category breakdown (expense)
final categoryBreakdownProvider =
    FutureProvider.family<List<CategoryTotal>, (String, String)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).categoryBreakdown(from: args.$1, to: args.$2, kind: 'expense');
});

// (from, to) → mode breakdown
final modeBreakdownProvider =
    FutureProvider.family<List<ModeTotal>, (String, String)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).modeBreakdown(from: args.$1, to: args.$2, kind: 'expense');
});

// (from, to) → top 10 expense categories by total spend
final topSpendsProvider =
    FutureProvider.family<List<CategoryTotal>, (String, String)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).topSpends(from: args.$1, to: args.$2);
});

// (accountId, from, to) → account statement
final accountStatementProvider =
    FutureProvider.family<List<Transaction>, (String, String, String)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).accountStatement(accountId: args.$1, from: args.$2, to: args.$3);
});

// (accountId, from, to) → account statement balances (opening, closing)
final accountStatementBalancesProvider =
    FutureProvider.family<(double, double), (String, String, String)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).accountStatementBalances(args.$1, args.$2, args.$3);
});

// Calculate current balance for a specific account
final accountBalanceProvider = Provider.family<AsyncValue<double>, String>((ref, accountId) {
  final txAsync = ref.watch(allTransactionsStreamProvider);
  final accAsync = ref.watch(accountsStreamProvider); // from manage_providers

  if (txAsync is AsyncLoading || accAsync is AsyncLoading) {
    return const AsyncLoading();
  }
  if (txAsync.hasError) return AsyncError(txAsync.error!, txAsync.stackTrace!);
  if (accAsync.hasError) return AsyncError(accAsync.error!, accAsync.stackTrace!);

  final account = (accAsync.valueOrNull ?? []).where((a) => a.id == accountId).firstOrNull;
  if (account == null) return const AsyncData(0.0);

  double total = account.openingBalance;

  for (final tx in txAsync.valueOrNull ?? []) {
    if (tx.accountId == accountId) {
      if (tx.kind == 'income' || tx.kind == 'transfer_in') {
        total += tx.amount;
      } else if (tx.kind == 'expense' || tx.kind == 'transfer_out') {
        total -= tx.amount;
      }
    }
  }

  return AsyncData(total);
});
