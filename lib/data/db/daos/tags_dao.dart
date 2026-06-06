import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/tags_table.dart';

part 'tags_dao.g.dart';

@DriftAccessor(tables: [Tags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.db);

  Stream<List<Tag>> watchAll() =>
      (select(tags)
            ..where((t) => t.isArchived.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<List<Tag>> getAllActive() =>
      (select(tags)..where((t) => t.isArchived.equals(false))).get();

  Future<Tag?> getById(String id) =>
      (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(TagsCompanion entry) =>
      into(tags).insertOnConflictUpdate(entry);

  Future<void> archive(String id) =>
      (update(tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          isArchived: const Value(true),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<int> hardDelete(String id) =>
      (delete(tags)..where((t) => t.id.equals(id))).go();
}
