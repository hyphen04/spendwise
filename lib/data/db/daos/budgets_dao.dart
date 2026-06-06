import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/budgets_table.dart';

part 'budgets_dao.g.dart';

@DriftAccessor(tables: [Budgets])
class BudgetsDao extends DatabaseAccessor<AppDatabase> with _$BudgetsDaoMixin {
  BudgetsDao(super.db);

  Stream<List<Budget>> watchAll() =>
      (select(budgets)..orderBy([(b) => OrderingTerm.asc(b.startDate)])).watch();

  Future<List<Budget>> getAll() => select(budgets).get();

  Future<Budget?> getById(String id) =>
      (select(budgets)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<void> upsert(BudgetsCompanion entry) =>
      into(budgets).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(budgets)..where((b) => b.id.equals(id))).go();
}
