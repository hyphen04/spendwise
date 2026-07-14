import 'package:drift/drift.dart';

import 'accounts_table.dart';
import 'categories_table.dart';
import 'modes_table.dart';

/// A recurring bill or subscription the user wants to track (e.g. Netflix ₹649
/// monthly, rent ₹12000 monthly, electricity quarterly).
///
/// Rows come from two sources:
/// - `source = 'detected'` — seeded by [LocalInsightEngine.detectRecurring]
///   over the user's expense history (one-time on upgrade to schema v13).
/// - `source = 'manual'` — the user added it themselves.
///
/// No PII columns: a recurring item is the user's own bill, not a contact. The
/// optional `note` stays on-device and is never sent to the AI (this table is
/// not in the LLM's schema metadata — see `schema_metadata.dart`).
class RecurringItems extends Table {
  TextColumn get id => text()();

  /// Human label, e.g. "Netflix", "Electricity bill".
  TextColumn get name => text()();

  /// The recurring amount (always positive).
  RealColumn get amount => real()();

  /// FK → categories.id (RESTRICT — reassign or remove the item first).
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();

  /// Optional FK → accounts.id (where it's paid from). Null = any account.
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();

  /// Optional FK → modes.id (how it's paid). Null = any mode.
  TextColumn get modeId =>
      text().nullable().references(Modes, #id, onDelete: KeyAction.setNull)();

  /// 'weekly' | 'fortnightly' | 'monthly' | 'quarterly' | 'yearly'
  TextColumn get cadence => text().withDefault(const Constant('monthly'))();

  /// ISO date of the next due date ('YYYY-MM-DD' or full ISO).
  TextColumn get nextDueDate => text()();

  /// ISO date of the last transaction that matched this recurring item, if
  /// detected. Null for manual items never matched.
  TextColumn get lastSeenDate => text().nullable()();

  /// 'detected' | 'manual'
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// Soft-delete / pause an item without losing its history.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Optional user note. Stays on-device; never sent to the AI.
  TextColumn get note => text().withDefault(const Constant(''))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}