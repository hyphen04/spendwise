import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';

class TagsRepository {
  TagsRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Tag>> watchAll() => _db.tagsDao.watchAll();
  Future<List<Tag>> getAllActive() => _db.tagsDao.getAllActive();

  Future<void> create({required String name, required String color}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.tagsDao.upsert(TagsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      color: Value(color),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> update(Tag existing, {required String name, required String color}) {
    return _db.tagsDao.upsert(TagsCompanion(
      id: Value(existing.id),
      name: Value(name),
      color: Value(color),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> archive(String id) => _db.tagsDao.archive(id);

  Future<int> countTransactions(String id) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(DISTINCT transaction_id) AS cnt FROM transaction_tags WHERE tag_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    return (row.data['cnt'] as int?) ?? 0;
  }

  Future<void> detachAndDelete(String id) =>
      _db.transaction(() async {
        await _db.customStatement(
          'DELETE FROM transaction_tags WHERE tag_id = ?',
          [id],
        );
        await _db.tagsDao.hardDelete(id);
      });
}
