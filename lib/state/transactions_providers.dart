import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';
import '../data/models/transaction_row.dart';
import '../data/repositories/transactions_repository.dart';
import 'database_provider.dart';
import 'manage_providers.dart';

final transactionsRepositoryProvider = Provider<TransactionsRepository>((ref) =>
    TransactionsRepository(ref.watch(appDatabaseProvider)));

final allTransactionsStreamProvider = StreamProvider<List<Transaction>>((ref) =>
    ref.watch(transactionsRepositoryProvider).watchAll());

final transactionsByMonthProvider =
    StreamProvider.family<List<Transaction>, (int, int)>((ref, args) =>
        ref.watch(transactionsRepositoryProvider).watchByMonth(args.$1, args.$2));

final transactionsSearchProvider =
    StreamProvider.family<List<Transaction>, String>((ref, query) =>
        query.isEmpty
            ? ref.watch(transactionsRepositoryProvider).watchAll()
            : ref.watch(transactionsRepositoryProvider).search(query));

/// All transactions enriched with account/category/mode names (Dart-level join).
final transactionRowsProvider = Provider<AsyncValue<List<TransactionRow>>>((ref) {
  final txAsync = ref.watch(allTransactionsStreamProvider);
  final accAsync = ref.watch(accountsStreamProvider);
  final catAsync = ref.watch(categoriesStreamProvider);
  final modeAsync = ref.watch(modesStreamProvider);

  return txAsync.whenData((txs) {
    final accMap = {for (final a in accAsync.valueOrNull ?? <Account>[]) a.id: a};
    final catMap = {for (final c in catAsync.valueOrNull ?? <Category>[]) c.id: c};
    final modeMap = {for (final m in modeAsync.valueOrNull ?? <Mode>[]) m.id: m};
    return txs
        .map((tx) => TransactionRow(
              transaction: tx,
              account: accMap[tx.accountId],
              category: catMap[tx.categoryId],
              mode: modeMap[tx.modeId],
            ))
        .toList();
  });
});
