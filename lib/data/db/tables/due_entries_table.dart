import 'package:drift/drift.dart';
import 'due_contacts_table.dart';
import 'due_settlements_table.dart';

class DueEntries extends Table {
  TextColumn get id => text()();
  
  /// FK -> due_contacts.id
  TextColumn get contactId => 
      text().references(DueContacts, #id, onDelete: KeyAction.restrict)();
      
  RealColumn get amount => real()();
  TextColumn get direction => text()(); // 'payable' or 'receivable'
  TextColumn get entryDate => text()(); // ISO 8601
  TextColumn get mealSlot => text().nullable()(); // 'lunch', 'dinner', or null
  TextColumn get note => text().withDefault(const Constant(''))();
  
  BoolColumn get isSettled => boolean().withDefault(const Constant(false))();
  
  /// FK -> due_settlements.id (Set when settled)
  TextColumn get settlementId => 
      text().nullable().references(DueSettlements, #id, onDelete: KeyAction.setNull)();
      
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
