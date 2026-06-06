import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/modes_table.dart';

part 'modes_dao.g.dart';

@DriftAccessor(tables: [Modes])
class ModesDao extends DatabaseAccessor<AppDatabase> with _$ModesDaoMixin {
  ModesDao(super.db);

  Stream<List<Mode>> watchAll() =>
      (select(modes)
            ..where((m) => m.isArchived.equals(false))
            ..orderBy([(m) => OrderingTerm.asc(m.name)]))
          .watch();

  Future<List<Mode>> getAllActive() =>
      (select(modes)..where((m) => m.isArchived.equals(false))).get();

  Future<Mode?> getById(String id) =>
      (select(modes)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<void> upsert(ModesCompanion entry) =>
      into(modes).insertOnConflictUpdate(entry);

  Future<void> archive(String id) =>
      (update(modes)..where((m) => m.id.equals(id))).write(
        ModesCompanion(
          isArchived: const Value(true),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<int> hardDelete(String id) =>
      (delete(modes)..where((m) => m.id.equals(id))).go();
}
