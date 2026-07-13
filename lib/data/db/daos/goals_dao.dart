import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/goals_table.dart';

part 'goals_dao.g.dart';

@DriftAccessor(tables: [Goals])
class GoalsDao extends DatabaseAccessor<AppDatabase> with _$GoalsDaoMixin {
  GoalsDao(super.db);

  /// Active goals first (most-relevant), then by target date ascending.
  Stream<List<Goal>> watchAll() => (select(goals)
        ..orderBy([
          (g) => OrderingTerm.desc(g.isActive),
          (g) => OrderingTerm.asc(g.targetDate),
        ]))
      .watch();

  Future<List<Goal>> getAll() => select(goals).get();

  Future<Goal?> getById(String id) =>
      (select(goals)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<void> upsert(GoalsCompanion entry) =>
      into(goals).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(goals)..where((g) => g.id.equals(id))).go();
}