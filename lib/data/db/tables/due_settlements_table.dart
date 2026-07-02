import 'package:drift/drift.dart';
import 'due_contacts_table.dart';
import 'transactions_table.dart';

class DueSettlements extends Table {
  TextColumn get id => text()();
  
  /// FK -> due_contacts.id
  TextColumn get contactId => 
      text().references(DueContacts, #id, onDelete: KeyAction.restrict)();
      
  RealColumn get totalAmount => real()();
  TextColumn get settledDate => text()(); // ISO 8601
  TextColumn get note => text().withDefault(const Constant(''))();
  
  /// FK -> transactions.id (If auto-created)
  TextColumn get linkedTransactionId => 
      text().nullable().references(Transactions, #id, onDelete: KeyAction.setNull)();
      
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
