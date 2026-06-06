import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';
import '../data/models/report_models.dart';
import '../data/repositories/reports_repository.dart';
import 'database_provider.dart';
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
  return ref.read(reportsRepositoryProvider).modeBreakdown(from: args.$1, to: args.$2);
});

// (from, to) → top 10 expense transactions
final topSpendsProvider =
    FutureProvider.family<List<Transaction>, (String, String)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).topSpends(from: args.$1, to: args.$2);
});

// (accountId, from, to) → account statement
final accountStatementProvider =
    FutureProvider.family<List<Transaction>, (String, String, String)>((ref, args) {
  ref.watch(allTransactionsStreamProvider);
  return ref.read(reportsRepositoryProvider).accountStatement(accountId: args.$1, from: args.$2, to: args.$3);
});

