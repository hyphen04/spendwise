import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions_table.dart';
import '../tables/transaction_tags_table.dart';
import '../tables/tags_table.dart';

part 'transactions_dao.g.dart';

@DriftAccessor(tables: [Transactions, TransactionTags, Tags])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  Stream<List<Transaction>> watchAll() =>
      (select(transactions)
            ..orderBy([
              (t) => OrderingTerm.desc(t.transactionDate),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

  Stream<List<Transaction>> watchByAccount(String accountId) =>
      (select(transactions)
            ..where((t) => t.accountId.equals(accountId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.transactionDate),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

  Stream<List<Transaction>> watchByMonth(int year, int month) {
    final from = DateTime(year, month).toIso8601String();
    final to = DateTime(year, month + 1).toIso8601String();
    return (select(transactions)
          ..where(
            (t) => t.transactionDate.isBiggerOrEqualValue(from) &
                t.transactionDate.isSmallerThanValue(to),
          )
          ..orderBy([
            (t) => OrderingTerm.desc(t.transactionDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<Transaction>> getForDateRange(
    DateTime from,
    DateTime to,
  ) =>
      (select(transactions)
            ..where(
              (t) =>
                  t.transactionDate.isBiggerOrEqualValue(from.toIso8601String()) &
                  t.transactionDate.isSmallerThanValue(to.toIso8601String()),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.transactionDate)]))
          .get();

  Stream<List<Transaction>> search(String query) {
    final q = '%${query.toLowerCase()}%';
    return (select(transactions)
          ..where(
            (t) => t.note.lower().like(q),
          )
          ..orderBy([
            (t) => OrderingTerm.desc(t.transactionDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<Transaction?> getById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Transaction>> getAllForExport() =>
      (select(transactions)..orderBy([(t) => OrderingTerm.asc(t.transactionDate)]))
          .get();

  Future<void> upsert(TransactionsCompanion entry) =>
      into(transactions).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  /// Returns the ID of an existing transaction that matches the import
  /// duplicate-key: full date/time, accountId, categoryId,
  /// modeId, amount, and note. Returns null if no duplicate exists.
  Future<String?> findDuplicate({
    required String transactionDate,
    required String accountId,
    required String categoryId,
    required String modeId,
    required double amount,
    required String note,
  }) async {
    final result = await customSelect(
      'SELECT id FROM transactions '
      'WHERE transaction_date = ? '
      '  AND account_id = ? '
      '  AND category_id = ? '
      '  AND mode_id = ? '
      '  AND amount = ? '
      '  AND note = ? '
      'LIMIT 1',
      variables: [
        Variable.withString(transactionDate),
        Variable.withString(accountId),
        Variable.withString(categoryId),
        Variable.withString(modeId),
        Variable.withReal(amount),
        Variable.withString(note),
      ],
    ).getSingleOrNull();
    return result?.data['id'] as String?;
  }

  // --- Tags ---

  Future<List<Tag>> getTagsForTransaction(String transactionId) async {
    final tagIds = await (select(transactionTags)
          ..where((tt) => tt.transactionId.equals(transactionId)))
        .get();
    if (tagIds.isEmpty) return [];
    final ids = tagIds.map((tt) => tt.tagId).toList();
    return (select(tags)..where((t) => t.id.isIn(ids))).get();
  }

  Future<void> setTagsForTransaction(
    String transactionId,
    List<String> tagIds,
  ) async {
    await (delete(transactionTags)
          ..where((tt) => tt.transactionId.equals(transactionId)))
        .go();
    for (final tagId in tagIds) {
      await into(transactionTags).insert(
        TransactionTagsCompanion.insert(
          transactionId: transactionId,
          tagId: tagId,
        ),
      );
    }
  }

  /// Returns the date of the oldest transaction, or null if table is empty.
  Future<DateTime?> earliestTransactionDate() async {
    final result = await customSelect(
      'SELECT MIN(transaction_date) AS earliest FROM transactions',
    ).getSingleOrNull();
    final val = result?.data['earliest'] as String?;
    return val == null ? null : DateTime.tryParse(val);
  }

  // --- Aggregates (used by home summary and reports) ---

  Future<double> sumAmountByKindAndMonth(
    String kind,
    int year,
    int month,
  ) async {
    final from = DateTime(year, month).toIso8601String();
    final to = DateTime(year, month + 1).toIso8601String();
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions '
      'WHERE kind = ? AND transaction_date >= ? AND transaction_date < ?',
      variables: [
        Variable.withString(kind),
        Variable.withString(from),
        Variable.withString(to),
      ],
    ).getSingle();
    return (result.data['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<Map<String, double>> categoryTotalsForMonth(
    int year,
    int month,
    String kind,
  ) async {
    final from = DateTime(year, month).toIso8601String();
    final to = DateTime(year, month + 1).toIso8601String();
    final rows = await customSelect(
      'SELECT categoryId, SUM(amount) AS total FROM transactions '
      'WHERE kind = ? AND transaction_date >= ? AND transaction_date < ? '
      'GROUP BY categoryId',
      variables: [
        Variable.withString(kind),
        Variable.withString(from),
        Variable.withString(to),
      ],
    ).get();
    return {
      for (final r in rows)
        r.data['categoryId'] as String: (r.data['total'] as num).toDouble(),
    };
  }
}
