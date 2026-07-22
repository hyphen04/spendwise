import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/models/transaction_row.dart';
import 'manage_providers.dart';
import 'transactions_providers.dart';

/// The user's most-frequently-used categories over the last ~60 days, used by
/// the Home quick-add rail. Derived reactively from [transactionRowsProvider]
/// (already loads all transactions + category joins) — no DB/SQL change.
///
/// Ranked by **transaction count** (frequency = "most used"), not spend amount.
/// Transfer legs are excluded (they carry no category). When there is no recent
/// history (a new user), falls back to the first few expense categories so the
/// rail is never empty.
final recentCategoriesProvider =
    Provider<AsyncValue<List<Category>>>((ref) {
  final rowsAsync = ref.watch(transactionRowsProvider);
  final catsAsync = ref.watch(categoriesStreamProvider);

  return rowsAsync.whenData((rows) {
    final cats = catsAsync.valueOrNull ?? <Category>[];
    final catMap = {for (final c in cats) c.id: c};

    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    final counts = <String, int>{};
    for (final r in rows) {
      final tx = r.transaction;
      // Transfers carry no category and aren't "spending" in a category sense.
      if (tx.kind == 'transfer_out' || tx.kind == 'transfer_in') continue;
      final cid = tx.categoryId;
      final dt = DateTime.tryParse(tx.transactionDate);
      if (dt == null || dt.isBefore(cutoff)) continue;
      counts[cid] = (counts[cid] ?? 0) + 1;
    }

    final sortedIds = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    final result = <Category>[];
    for (final id in sortedIds) {
      final c = catMap[id];
      if (c != null && !c.isArchived) result.add(c);
      if (result.length >= 5) break;
    }

    // New-user fallback: show the first few expense categories so the rail
    // isn't empty before there's enough history to rank by frequency.
    if (result.isEmpty) {
      return cats
          .where((c) => !c.isArchived && c.kind != 'income')
          .take(5)
          .toList();
    }
    return result;
  });
});

/// The amount the user last logged for [categoryId] — the most recent
/// transaction in that category — or null when there's no history for it. Used
/// to prefill the Home quick-add sheet so a repeat purchase is one tap: open →
/// last amount already filled in → ✓. On-device, derived reactively from
/// [transactionRowsProvider]; no DB/SQL change. Transfer legs are excluded.
final lastAmountForCategoryProvider =
    Provider.family<double?, String>((ref, categoryId) {
  final rows =
      ref.watch(transactionRowsProvider).valueOrNull ?? const <TransactionRow>[];
  TransactionRow? latest;
  for (final r in rows) {
    final tx = r.transaction;
    if (tx.kind == 'transfer_out' || tx.kind == 'transfer_in') continue;
    if (tx.categoryId != categoryId) continue;
    if (latest == null) {
      latest = r;
      continue;
    }
    final a = DateTime.tryParse(tx.transactionDate);
    final b = DateTime.tryParse(latest.transaction.transactionDate);
    if (a != null && b != null && a.isAfter(b)) latest = r;
  }
  return latest?.transaction.amount;
});