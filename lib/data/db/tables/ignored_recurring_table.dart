import 'package:drift/drift.dart';

import 'categories_table.dart';

/// Categories the user has marked "not a recurring bill" via the Bills screen's
/// "Not a bill" action on a detected item. The detector
/// (`RecurringRepository.autoRefreshFromTransactions`) skips any detected group
/// whose category id is listed here, so a false positive like Fuel isn't
/// re-seeded every time detection re-runs (deleting the row alone wouldn't
/// stick — re-detect would resurrect it).
///
/// **No PII** — just a category id. Never queried by AI tools, never listed in
/// `schema_metadata`, never sent to the LLM. The user can still manually add a
/// bill in an ignored category; this list only suppresses auto-detection.
class IgnoredRecurring extends Table {
  /// The category that should never be auto-detected as recurring.
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {categoryId};
}