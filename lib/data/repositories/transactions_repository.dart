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
        amount: amount,
        transactionDate: transactionDate,
        accountId: fromAccountId,
        categoryId: catId,
        modeId: modeId,
        kind: const Value('transfer_out'),
        note: Value(note),
        transferPairId: Value(incomeId),
        createdAt: now,
        updatedAt: now,
      ));
      await _db.transactionsDao.upsert(TransactionsCompanion.insert(
        id: incomeId,
        amount: amount,
        transactionDate: transactionDate,
        accountId: toAccountId,
        categoryId: catId,
        modeId: modeId,
        kind: const Value('transfer_in'),
        note: Value(note),
        transferPairId: Value(expenseId),
        createdAt: now,
        updatedAt: now,
      ));
    });
  }

  Future<void> updateTransfer(
    Transaction existing, {
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
      final isExistingTransferIn = existing.kind == 'transfer_in';
      
      final existingAccountId = isExistingTransferIn ? toAccountId : fromAccountId;
      final pairAccountId = isExistingTransferIn ? fromAccountId : toAccountId;

      // Update the leg we opened for editing
      await _db.transactionsDao.upsert(TransactionsCompanion(
        id: Value(existing.id),
        amount: Value(amount),
        transactionDate: Value(transactionDate),
        accountId: Value(existingAccountId),
        modeId: Value(modeId),
        note: Value(note),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(now),
      ));
      // Update the other leg if the pair exists
      if (pair != null) {
        await _db.transactionsDao.upsert(TransactionsCompanion(
          id: Value(pair.id),
          amount: Value(amount),
          transactionDate: Value(transactionDate),
          accountId: Value(pairAccountId),
          modeId: Value(modeId),
          note: Value(note),
          createdAt: Value(pair.createdAt),
          updatedAt: Value(now),
        ));
      }
    });
  }

  /// Creates a faithful copy of [tx] — same amount/date/account/category/mode/
  /// note/tags. For transfers, both legs are recreated via [createTransfer].
  ///
  /// The original `transactionDate` is preserved; the user can open the new row
  /// and change the date if they want it "now". Returns the new transaction id
  /// for plain transactions (empty string for transfers — createTransfer has no
  /// return value).
  Future<String> duplicate(Transaction tx) async {
    if (tx.kind == 'transfer_out' || tx.kind == 'transfer_in') {
      final pair = await getById(tx.transferPairId!);
      final from = tx.kind == 'transfer_out' ? tx.accountId : pair!.accountId;
      final to = tx.kind == 'transfer_out' ? pair!.accountId : tx.accountId;
      await createTransfer(
        amount: tx.amount,
        transactionDate: tx.transactionDate,
        fromAccountId: from,
        toAccountId: to,
        modeId: tx.modeId,
        note: tx.note,
      );
      return '';
    }
    final tagIds = await getTagsFor(tx.id);
    return create(
      amount: tx.amount,
      transactionDate: tx.transactionDate,
      accountId: tx.accountId,
      categoryId: tx.categoryId,
      modeId: tx.modeId,
      kind: tx.kind,
      note: tx.note,
      tagIds: tagIds.map((t) => t.id).toList(),
    );
  }

  Future<void> delete(String id) async {
    final tx = await getById(id);
    if (tx == null) return;
    if (tx.kind.startsWith('transfer') && tx.transferPairId != null) {
      await _db.transaction(() async {
        await _db.transactionsDao.deleteById(tx.transferPairId!);
        await _db.transactionsDao.deleteById(id);
      });
    } else {
      await _db.transactionsDao.deleteById(id);
    }
  }
}
