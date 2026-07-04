import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../db/daos/dues_dao.dart';

class DueContactSummary {
  const DueContactSummary({
    required this.contact,
    required this.balance,
    required this.unsettledCount,
  });

  final DueContact contact;
  final double balance;
  final int unsettledCount;
}

class DuesRepository {
  DuesRepository(this._db);
  final AppDatabase _db;
  
  final _uuid = const Uuid();

  // --- Contacts ---

  Stream<List<DueContact>> watchAllContacts() =>
      _db.duesDao.watchAllContacts();

  Future<DueContactSummary> getContactSummary(String contactId) async {
    final contact = await (_db.select(_db.dueContacts)
          ..where((c) => c.id.equals(contactId)))
        .getSingle();
        
    final entries = await (_db.select(_db.dueEntries)
          ..where((e) => e.contactId.equals(contactId) & e.isSettled.equals(false)))
        .get();

    double balance = 0;
    for (final e in entries) {
      if (e.direction == 'receivable') {
        balance += e.amount;
      } else {
        balance -= e.amount;
      }
    }
    
    return DueContactSummary(
      contact: contact,
      balance: balance,
      unsettledCount: entries.length,
    );
  }

  Future<String> createContact({
    required String name,
    required String icon,
    required String color,
    required String type,
    double? defaultAmount,
    String? defaultNote,
    String? defaultCategoryId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await _db.duesDao.upsertContact(
      DueContactsCompanion.insert(
        id: id,
        name: name,
        icon: icon,
        color: color,
        type: Value(type),
        defaultAmount: Value(defaultAmount),
        defaultNote: Value(defaultNote),
        defaultCategoryId: Value(defaultCategoryId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> updateContact(
    DueContact existing, {
    required String name,
    required String icon,
    required String color,
    required String type,
    double? defaultAmount,
    String? defaultNote,
    String? defaultCategoryId,
  }) async {
    await _db.duesDao.upsertContact(
      DueContactsCompanion(
        id: Value(existing.id),
        name: Value(name),
        icon: Value(icon),
        color: Value(color),
        type: Value(type),
        defaultAmount: Value(defaultAmount),
        defaultNote: Value(defaultNote),
        defaultCategoryId: Value(defaultCategoryId),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> archiveContact(String id, bool archive) async {
    await (_db.update(_db.dueContacts)..where((c) => c.id.equals(id))).write(
      DueContactsCompanion(
        isArchived: Value(archive),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deleteContact(String id) async {
    // This will fail if there are entries (RESTRICT), which is desired.
    // The user should settle or delete entries first.
    await _db.duesDao.deleteContact(id);
  }

  // --- Entries ---

  Stream<List<DueEntry>> watchUnsettledEntries(String contactId) =>
      _db.duesDao.watchUnsettledEntries(contactId);

  Future<String> addEntry({
    required String contactId,
    required double amount,
    required String direction,
    required DateTime date,
    String? mealSlot,
    String note = '',
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await _db.duesDao.upsertEntry(
      DueEntriesCompanion.insert(
        id: id,
        contactId: contactId,
        amount: amount,
        direction: direction,
        entryDate: date.toIso8601String(),
        mealSlot: Value(mealSlot),
        note: Value(note),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> updateEntry(
    DueEntry existing, {
    required double amount,
    required String direction,
    required DateTime date,
    String? mealSlot,
    required String note,
  }) async {
    await _db.duesDao.upsertEntry(
      DueEntriesCompanion(
        id: Value(existing.id),
        contactId: Value(existing.contactId),
        amount: Value(amount),
        direction: Value(direction),
        entryDate: Value(date.toIso8601String()),
        mealSlot: Value(mealSlot),
        note: Value(note),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deleteEntry(String id) => _db.duesDao.deleteEntry(id);

  // --- Settlements ---

  Stream<List<DueSettlement>> watchSettlements(String contactId) =>
      _db.duesDao.watchSettlements(contactId);

  Stream<List<DueSettlementWithCount>> watchSettlementsWithCount(String contactId) =>
      _db.duesDao.watchSettlementsWithCount(contactId);

  Future<DueSettlement?> getSettlementForTransaction(String transactionId) =>
      _db.duesDao.getSettlementForTransaction(transactionId);

  Future<void> undoSettlement(String settlementId) =>
      _db.duesDao.undoSettlement(settlementId);

  Future<void> deleteSettlement(String settlementId) async {
    final settlement = await _db.duesDao.getSettlementById(settlementId);
    if (settlement == null) return;
    
    // Unlink entries and delete the settlement record
    await undoSettlement(settlementId);
    
    // Delete the linked transaction if it exists
    if (settlement.linkedTransactionId != null) {
      await _db.transactionsDao.deleteById(settlement.linkedTransactionId!);
    }
  }

  Future<void> settleEntries({
    required String contactId,
    required List<String> entryIds,
    required double totalAmount,
    required String note,
    required DateTime date,
    
    // If auto-creating an expense/income transaction
    bool createLinkedTransaction = false,
    String? accountId,
    String? categoryId,
    String? modeId,
    String? transactionKind,
  }) async {
    final settlementId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    TransactionsCompanion? linkedTx;
    
    if (createLinkedTransaction && accountId != null && categoryId != null && modeId != null && transactionKind != null) {
      linkedTx = TransactionsCompanion.insert(
        id: _uuid.v4(),
        amount: totalAmount,
        transactionDate: date.toIso8601String(),
        accountId: accountId,
        categoryId: categoryId,
        modeId: modeId,
        kind: Value(transactionKind),
        note: Value(note),
        createdAt: now,
        updatedAt: now,
      );
    }

    await _db.duesDao.settleEntries(
      contactId: contactId,
      entryIds: entryIds,
      settlement: DueSettlementsCompanion.insert(
        id: settlementId,
        contactId: contactId,
        totalAmount: totalAmount,
        settledDate: date.toIso8601String(),
        note: Value(note),
        createdAt: now,
        updatedAt: now,
      ),
      linkedTransaction: linkedTx,
    );
  }

  // --- Aggregates ---
  
  Future<Map<String, double>> getAllContactBalances() => _db.duesDao.getAllContactBalances();
  
  Future<(int, double)> getMonthlyVendorStats(String contactId, int year, int month) => 
      _db.duesDao.getMonthlyVendorStats(contactId, year, month);

  Future<List<DueEntry>> getEntriesForSettlement(String settlementId) =>
      _db.duesDao.getEntriesForSettlement(settlementId);
}
