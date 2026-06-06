import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';

class AccountsRepository {
  AccountsRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Account>> watchAll() => _db.accountsDao.watchAll();
  Future<List<Account>> getAllActive() => _db.accountsDao.getAllActive();

  Future<void> create({
    required String name,
    required String icon,
    required String color,
    double openingBalance = 0,
    String currency = 'INR',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.accountsDao.upsert(AccountsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      icon: icon,
      color: color,
      openingBalance: Value(openingBalance),
      currency: Value(currency),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> update(
    Account existing, {
    required String name,
    required String icon,
    required String color,
    required double openingBalance,
    required String currency,
  }) {
    return _db.accountsDao.upsert(AccountsCompanion(
      id: Value(existing.id),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      openingBalance: Value(openingBalance),
      currency: Value(currency),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> archive(String id) => _db.accountsDao.archive(id);

  Future<int> countTransactions(String id) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS cnt FROM transactions WHERE account_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    return (row.data['cnt'] as int?) ?? 0;
  }

  Future<void> reassignAndDelete(String oldId, String newId) =>
      _db.transaction(() async {
        await _db.customStatement(
          'UPDATE transactions SET account_id = ? WHERE account_id = ?',
          [newId, oldId],
        );
        await _db.accountsDao.hardDelete(oldId);
      });
}
