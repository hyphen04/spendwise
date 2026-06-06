import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';

class CategoriesRepository {
  CategoriesRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Category>> watchAll() => _db.categoriesDao.watchAll();
  Stream<List<Category>> watchByKind(String kind) =>
      _db.categoriesDao.watchByKind(kind);
  Future<List<Category>> getAllActive() => _db.categoriesDao.getAllActive();

  Future<void> create({
    required String name,
    required String icon,
    required String color,
    String kind = 'expense',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.categoriesDao.upsert(CategoriesCompanion.insert(
      id: _uuid.v4(),
      name: name,
      icon: icon,
      color: Value(color),
      kind: Value(kind),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> update(
    Category existing, {
    required String name,
    required String icon,
    required String color,
    required String kind,
  }) {
    return _db.categoriesDao.upsert(CategoriesCompanion(
      id: Value(existing.id),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      kind: Value(kind),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> archive(String id) => _db.categoriesDao.archive(id);

  Future<int> countTransactions(String id) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS cnt FROM transactions WHERE category_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    return (row.data['cnt'] as int?) ?? 0;
  }

  Future<void> reassignAndDelete(String oldId, String newId) =>
      _db.transaction(() async {
        await _db.customStatement(
          'UPDATE transactions SET category_id = ? WHERE category_id = ?',
          [newId, oldId],
        );
        await _db.categoriesDao.hardDelete(oldId);
      });
}
