import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/custom_reports_table.dart';

part 'custom_reports_dao.g.dart';

/// CRUD for saved custom-report specs. The spec JSON is opaque to the DAO — it
/// only stores/retrieves the string; (de)serialization lives in
/// `custom_report_spec.dart`. No PII ever flows through here.
@DriftAccessor(tables: [CustomReports])
class CustomReportsDao extends DatabaseAccessor<AppDatabase>
    with _$CustomReportsDaoMixin {
  CustomReportsDao(super.db);

  /// All saved reports, newest-first.
  Stream<List<CustomReport>> watchAll() => (select(customReports)
        ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]))
      .watch();

  Future<List<CustomReport>> getAll() => select(customReports).get();

  Future<CustomReport?> getById(String id) =>
      (select(customReports)..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Insert or replace by id. Use only for fresh inserts — the companion must
  /// supply every NOT NULL column (including `createdAt`), because
  /// `insertOnConflictUpdate` validates the INSERT statement before the
  /// ON CONFLICT update runs. For editing an existing row, use [updateFields]
  /// (which leaves `createdAt` untouched and avoids that validation).
  Future<void> upsert(CustomReportsCompanion entry) =>
      into(customReports).insertOnConflictUpdate(entry);

  /// Update an existing report's name + spec + `updatedAt` by id. `createdAt`
  /// is intentionally not written, so the original creation timestamp survives.
  /// Returns true if a row was matched.
  Future<bool> updateFields(
    String id, {
    required String name,
    required String specJson,
    required int updatedAt,
  }) =>
      (update(customReports)..where((r) => r.id.equals(id)))
          .write(CustomReportsCompanion(
            name: Value(name),
            specJson: Value(specJson),
            updatedAt: Value(updatedAt),
          ))
          .then((rows) => rows > 0);

  Future<int> deleteById(String id) =>
      (delete(customReports)..where((r) => r.id.equals(id))).go();
}