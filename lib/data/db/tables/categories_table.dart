import 'package:drift/drift.dart';

/// Transaction kind this category applies to.
/// 'expense' | 'income' | 'both'
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()(); // emoji or icon name
  TextColumn get color => text().withDefault(const Constant('#059669'))();
  TextColumn get kind => text().withDefault(const Constant('expense'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
