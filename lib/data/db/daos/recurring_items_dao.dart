import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/recurring_items_table.dart';

part 'recurring_items_dao.g.dart';

@DriftAccessor(tables: [RecurringItems])
class RecurringItemsDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringItemsDaoMixin {
  RecurringItemsDao(super.db);

  /// All recurring items, active first, then by next due date ascending.
  Stream<List<RecurringItem>> watchAll() => (select(recurringItems)
        ..orderBy([
          (r) => OrderingTerm.desc(r.isActive),
          (r) => OrderingTerm.asc(r.nextDueDate),
        ]))
      .watch();

  Future<List<RecurringItem>> getAll() => select(recurringItems).get();

  Future<RecurringItem?> getById(String id) =>
      (select(recurringItems)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<void> upsert(RecurringItemsCompanion entry) =>
      into(recurringItems).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(recurringItems)..where((r) => r.id.equals(id))).go();
}