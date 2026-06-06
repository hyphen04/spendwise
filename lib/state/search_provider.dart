import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';
import '../data/models/transaction_row.dart';
import 'manage_providers.dart';
import 'transactions_providers.dart';

class GlobalSearchResults {
  const GlobalSearchResults({
    required this.transactions,
    required this.categories,
    required this.accounts,
    required this.modes,
    required this.tags,
  });

  const GlobalSearchResults.empty()
      : transactions = const [],
        categories = const [],
        accounts = const [],
        modes = const [],
        tags = const [];

  final List<TransactionRow> transactions;
  final List<Category> categories;
  final List<Account> accounts;
  final List<Mode> modes;
  final List<Tag> tags;

  bool get isEmpty =>
      transactions.isEmpty &&
      categories.isEmpty &&
      accounts.isEmpty &&
      modes.isEmpty &&
      tags.isEmpty;
}

final globalSearchProvider =
    Provider.family<GlobalSearchResults, String>((ref, query) {
  if (query.isEmpty) return const GlobalSearchResults.empty();
  final q = query.toLowerCase();

  // Transactions — enriched rows (title, note, amount, category/account/mode name)
  final txRows = ref.watch(transactionRowsProvider).valueOrNull ?? [];
  final matchedTx = txRows.where((row) {
    final tx = row.transaction;
    if (tx.title.toLowerCase().contains(q)) return true;
    if (tx.note.toLowerCase().contains(q)) return true;
    if (tx.amount.toString().contains(q)) return true;
    if (tx.amount.toInt().toString().contains(q)) return true;
    if (row.category?.name.toLowerCase().contains(q) ?? false) return true;
    if (row.account?.name.toLowerCase().contains(q) ?? false) return true;
    if (row.mode?.name.toLowerCase().contains(q) ?? false) return true;
    return false;
  }).take(25).toList();

  final cats = (ref.watch(categoriesStreamProvider).valueOrNull ?? [])
      .where((c) => !c.isArchived && c.name.toLowerCase().contains(q))
      .take(5)
      .toList();

  final accs = (ref.watch(accountsStreamProvider).valueOrNull ?? [])
      .where((a) => !a.isArchived && a.name.toLowerCase().contains(q))
      .take(5)
      .toList();

  final modes = (ref.watch(modesStreamProvider).valueOrNull ?? [])
      .where((m) => !m.isArchived && m.name.toLowerCase().contains(q))
      .take(5)
      .toList();

  final tags = (ref.watch(tagsStreamProvider).valueOrNull ?? [])
      .where((t) => !t.isArchived && t.name.toLowerCase().contains(q))
      .take(5)
      .toList();

  return GlobalSearchResults(
    transactions: matchedTx,
    categories: cats,
    accounts: accs,
    modes: modes,
    tags: tags,
  );
});

/// Last 5 transactions for the empty-state "Recent" list.
final recentTransactionsProvider = Provider<List<TransactionRow>>((ref) {
  return (ref.watch(transactionRowsProvider).valueOrNull ?? []).take(5).toList();
});
