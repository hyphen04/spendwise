import 'package:drift/drift.dart';
import 'accounts_table.dart';

/// Savings goals (e.g. "New phone ₹60,000"). Distinct from spend-cap budgets:
/// a goal is a *target to reach*, tracked by `savedAmount` vs `targetAmount`.
///
/// No PII columns — a goal is the user's own target (name/icon/color). Like
/// `recurring_items`, this table is **not** part of the AI schema metadata and
/// never leaves the device.
class Goals extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant('🎯'))();
  TextColumn get color => text().withDefault(const Constant('#2563EB'))();

  /// Amount the user wants to save.
  RealColumn get targetAmount => real()();

  /// Amount saved so far (advanced by contributions; never decremented by the
  /// app — the user owns this number).
  RealColumn get savedAmount => real().withDefault(const Constant(0))();

  /// Optional target date (ISO date 'YYYY-MM-DD'). Null = no deadline.
  TextColumn get targetDate => text().nullable()();

  /// Optional account this goal is funded from / tracked against.
  TextColumn get linkedAccountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();

  /// Optional "Save More Tomorrow" monthly auto-commitment (₹/month). Stored
  /// for display/projection only — the app does not auto-move money.
  RealColumn get monthlyCommitment => real().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}