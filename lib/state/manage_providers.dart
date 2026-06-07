import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';
import '../data/repositories/accounts_repository.dart';
import '../data/repositories/categories_repository.dart';
import '../data/repositories/modes_repository.dart';
import 'database_provider.dart';

// ── Repositories ─────────────────────────────────────────────────────────────

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) =>
    AccountsRepository(ref.watch(appDatabaseProvider)));

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) =>
    CategoriesRepository(ref.watch(appDatabaseProvider)));

final modesRepositoryProvider = Provider<ModesRepository>((ref) =>
    ModesRepository(ref.watch(appDatabaseProvider)));

// ── Streams ───────────────────────────────────────────────────────────────────

final accountsStreamProvider = StreamProvider<List<Account>>((ref) =>
    ref.watch(accountsRepositoryProvider).watchAll());

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) =>
    ref.watch(categoriesRepositoryProvider).watchAll());

/// Filtered by kind: 'expense' | 'income' | 'both'
final categoriesByKindProvider =
    StreamProvider.family<List<Category>, String>((ref, kind) =>
        ref.watch(categoriesRepositoryProvider).watchByKind(kind));

final modesStreamProvider = StreamProvider<List<Mode>>((ref) =>
    ref.watch(modesRepositoryProvider).watchAll());

/// Net balance for a single account:
///   openingBalance + SUM(income transactions) − SUM(expense transactions)
/// Reacts to both account edits and transaction changes.
final accountNetBalanceProvider =
    StreamProvider.family<double, Account>((ref, account) {
  final db = ref.watch(appDatabaseProvider);
  // watchByAccount emits a new list every time a transaction for this account
  // is added, edited or deleted — which triggers a recompute.
  return db.transactionsDao.watchByAccount(account.id).map((txs) {
    double income = 0, expense = 0;
    for (final tx in txs) {
      if (tx.kind == 'income') {
        income += tx.amount;
      } else if (tx.kind == 'expense') {
        expense += tx.amount;
      }
    }
    return account.openingBalance + income - expense;
  });
});

