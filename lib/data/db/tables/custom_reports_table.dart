import 'package:drift/drift.dart';

/// User-authored custom report definitions (the "Your Reports" section of the
/// Reports hub). A row is a saved [CustomReportSpec] serialized to JSON.
///
/// **No PII.** The spec is purely field references + filters (groupBy / metric /
/// kind / dateRange / account-category-mode-tag ids / chartType) — it never
/// stores transaction notes, contact names/phones, receipt paths, or any raw
/// row data. The spec is executed on-device by `CustomReportExecutor` against
/// the safe table subset (transactions + accounts/categories/modes/tags) and is
/// **never sent to the LLM**.
///
/// Like `goals`, this table is not part of the AI schema metadata and never
/// leaves the device.
class CustomReports extends Table {
  TextColumn get id => text()();

  /// Human-readable name shown in the "Your Reports" list.
  TextColumn get name => text()();

  /// Serialized [CustomReportSpec] JSON (see `custom_report_spec.dart`).
  TextColumn get specJson => text()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}