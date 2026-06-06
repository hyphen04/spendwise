import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/categories_table.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Stream<List<Category>> watchAll() =>
      (select(categories)
            ..where((c) => c.isArchived.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  Stream<List<Category>> watchByKind(String kind) =>
      (select(categories)
            ..where(
              (c) => c.isArchived.equals(false) &
                  (c.kind.equals(kind) | c.kind.equals('both')),
            )
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  Future<List<Category>> getAllActive() =>
      (select(categories)..where((c) => c.isArchived.equals(false))).get();

  Future<Category?> getById(String id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<void> upsert(CategoriesCompanion entry) =>
      into(categories).insertOnConflictUpdate(entry);

  Future<void> archive(String id) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          isArchived: const Value(true),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<int> hardDelete(String id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();
}
