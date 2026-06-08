import 'package:drift/drift.dart';
import 'accounts_table.dart';
import 'categories_table.dart';
import 'modes_table.dart';
class Transactions extends Table {
  TextColumn get id => text()();
  RealColumn get amount => real()();
  TextColumn get transactionDate => text()(); // ISO 8601

  /// FK → accounts.id
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.restrict)();

  /// FK → categories.id
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();

  /// FK → modes.id
  TextColumn get modeId =>
      text().references(Modes, #id, onDelete: KeyAction.restrict)();

  /// 'expense' | 'income' | 'transfer'
  TextColumn get kind => text().withDefault(const Constant('expense'))();

  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get receiptPath => text().nullable()();

  /// For transfers: links the matching counter-leg transaction.
  TextColumn get transferPairId => text().nullable()();

  /// Legacy id from sqflite era; kept for traceability during migration only.
  TextColumn get legacyId => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
