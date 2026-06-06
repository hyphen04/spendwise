import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';

class ModesRepository {
  ModesRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Mode>> watchAll() => _db.modesDao.watchAll();
  Future<List<Mode>> getAllActive() => _db.modesDao.getAllActive();

  Future<void> create({
    required String name,
    required String icon,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.modesDao.upsert(ModesCompanion.insert(
      id: _uuid.v4(),
      name: name,
      icon: icon,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> update(Mode existing, {required String name, required String icon}) {
    return _db.modesDao.upsert(ModesCompanion(
      id: Value(existing.id),
      name: Value(name),
      icon: Value(icon),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> archive(String id) => _db.modesDao.archive(id);

  Future<int> countTransactions(String id) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS cnt FROM transactions WHERE mode_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    return (row.data['cnt'] as int?) ?? 0;
  }

  Future<void> reassignAndDelete(String oldId, String newId) =>
      _db.transaction(() async {
        await _db.customStatement(
          'UPDATE transactions SET mode_id = ? WHERE mode_id = ?',
          [newId, oldId],
        );
        await _db.modesDao.hardDelete(oldId);
      });
}
