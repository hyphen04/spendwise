import 'package:drift/drift.dart';

class DueContacts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  TextColumn get color => text()();
  TextColumn get type => text().withDefault(const Constant('vendor'))(); // 'vendor' or 'person'
  RealColumn get defaultAmount => real().nullable()();
  TextColumn get defaultNote => text().nullable()();
  TextColumn get defaultCategoryId => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
