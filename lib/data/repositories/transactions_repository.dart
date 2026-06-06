import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';

class TransactionsRepository {
  TransactionsRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<List<Transaction>> watchAll() => _db.transactionsDao.watchAll();

  Stream<List<Transaction>> watchByMonth(int year, int month) =>
      _db.transactionsDao.watchByMonth(year, month);

  Stream<List<Transaction>> search(String query) =>
      _db.transactionsDao.search(query);

  // ── Single ops ─────────────────────────────────────────────────────────────

  Future<Transaction?> getById(String id) =>
      _db.transactionsDao.getById(id);

  Future<List<Tag>> getTagsFor(String transactionId) =>
      _db.transactionsDao.getTagsForTransaction(transactionId);

  Future<void> setTagsFor(String transactionId, List<String> tagIds) =>
      _db.transactionsDao.setTagsForTransaction(transactionId, tagIds);

  // ── Write ops ──────────────────────────────────────────────────────────────

  Future<String> create({
    required String title,
    required double amount,
    required String transactionDate,
    required String accountId,
    required String categoryId,
    required String modeId,
    required String kind,
    String note = '',
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await _db.transactionsDao.upsert(TransactionsCompanion.insert(
      id: id,
      title: title,
      amount: amount,
      transactionDate: transactionDate,
      accountId: accountId,
      categoryId: categoryId,
      modeId: modeId,
      kind: Value(kind),
      note: Value(note),
      createdAt: now,
      updatedAt: now,
    ));
    if (tagIds.isNotEmpty) {
      await _db.transactionsDao.setTagsForTransaction(id, tagIds);
    }
    return id;
  }

  Future<void> update(
    Transaction existing, {
    required String title,
    required double amount,
    required String transactionDate,
    required String accountId,
    required String categoryId,
    required String modeId,
    required String kind,
    required String note,
    List<String>? tagIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transactionsDao.upsert(TransactionsCompanion(
      id: Value(existing.id),
      title: Value(title),
      amount: Value(amount),
      transactionDate: Value(transactionDate),
      accountId: Value(accountId),
      categoryId: Value(categoryId),
      modeId: Value(modeId),
      kind: Value(kind),
      note: Value(note),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(now),
    ));
    if (tagIds != null) {
      await _db.transactionsDao.setTagsForTransaction(existing.id, tagIds);
    }
  }

  /// Creates a transfer pair: expense leg from [fromAccountId] and income
  /// leg to [toAccountId], linked via [transferPairId].
  Future<void> createTransfer({
    required String title,
    required double amount,
    required String transactionDate,
    required String fromAccountId,
    required String toAccountId,
    required String modeId,
    String note = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expenseId = _uuid.v4();
    final incomeId = _uuid.v4();
    final catId = AppDatabase.kTransferCategoryId;

    await _db.transaction(() async {
      await _db.transactionsDao.upsert(TransactionsCompanion.insert(
        id: expenseId,
        title: title,
        amount: amount,
        transactionDate: transactionDate,
        accountId: fromAccountId,
        categoryId: catId,
        modeId: modeId,
        kind: const Value('transfer'),
        note: Value(note),
        transferPairId: Value(incomeId),
        createdAt: now,
        updatedAt: now,
      ));
      await _db.transactionsDao.upsert(TransactionsCompanion.insert(
        id: incomeId,
        title: title,
        amount: amount,
        transactionDate: transactionDate,
        accountId: toAccountId,
        categoryId: catId,
        modeId: modeId,
        kind: const Value('transfer'),
        note: Value(note),
        transferPairId: Value(expenseId),
        createdAt: now,
        updatedAt: now,
      ));
    });
  }

  Future<void> updateTransfer(
    Transaction existing, {
    required String title,
    required double amount,
    required String transactionDate,
    required String fromAccountId,
    required String toAccountId,
    required String modeId,
    required String note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pairId = existing.transferPairId;
    final pair = pairId != null ? await _db.transactionsDao.getById(pairId) : null;

    await _db.transaction(() async {
      // Update the expense leg (the one we opened for editing)
      await _db.transactionsDao.upsert(TransactionsCompanion(
        id: Value(existing.id),
        title: Value(title),
        amount: Value(amount),
        transactionDate: Value(transactionDate),
        accountId: Value(fromAccountId),
        modeId: Value(modeId),
        note: Value(note),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(now),
      ));
      // Update the income leg if the pair exists
      if (pair != null) {
        await _db.transactionsDao.upsert(TransactionsCompanion(
          id: Value(pair.id),
          title: Value(title),
          amount: Value(amount),
          transactionDate: Value(transactionDate),
          accountId: Value(toAccountId),
          modeId: Value(modeId),
          note: Value(note),
          createdAt: Value(pair.createdAt),
          updatedAt: Value(now),
        ));
      }
    });
  }

  Future<void> duplicate(Transaction tx) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transactionsDao.upsert(TransactionsCompanion.insert(
      id: _uuid.v4(),
      title: tx.title,
      amount: tx.amount,
      transactionDate: DateTime.now().toIso8601String(),
      accountId: tx.accountId,
      categoryId: tx.categoryId,
      modeId: tx.modeId,
      kind: Value(tx.kind),
      note: Value(tx.note),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> delete(String id) async {
    final tx = await getById(id);
    if (tx == null) return;
    if (tx.kind == 'transfer' && tx.transferPairId != null) {
      await _db.transaction(() async {
        await _db.transactionsDao.deleteById(tx.transferPairId!);
        await _db.transactionsDao.deleteById(id);
      });
    } else {
      await _db.transactionsDao.deleteById(id);
    }
  }
}
