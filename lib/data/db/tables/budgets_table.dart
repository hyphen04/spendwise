import 'package:drift/drift.dart';
import 'categories_table.dart';
import 'accounts_table.dart';

class Budgets extends Table {
  TextColumn get id => text()();

  /// FK → categories.id (RESTRICT on delete — user must reassign or remove budget first)
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();

  /// Null = applies to all accounts
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();

  /// 'month' | 'week'
  TextColumn get period => text().withDefault(const Constant('month'))();
  RealColumn get amount => real()();
  TextColumn get startDate => text()(); // ISO date 'YYYY-MM-DD'

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
