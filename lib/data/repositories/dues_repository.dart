import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../app/utils/phone_utils.dart';
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
    String? phone,
    String? photoPath,
    String? deviceContactId,
    List<ContactPhone>? phones,
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
        phone: Value(phone),
        photoPath: Value(photoPath),
        deviceContactId: Value(deviceContactId),
        phones: Value(phones == null || phones.isEmpty ? null : ContactPhone.encode(phones)),
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
    String? phone,
    String? photoPath,
    String? deviceContactId,
    List<ContactPhone>? phones,
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
        phone: Value(phone),
        photoPath: Value(photoPath),
        deviceContactId: Value(deviceContactId),
        phones: Value(phones == null || phones.isEmpty ? null : ContactPhone.encode(phones)),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Every phone number attached to [contact], for the call/WhatsApp chooser.
  ///
  /// Decodes the `phones` JSON column; if that's empty (a contact created
  /// before v11 or one with a single legacy number), falls back to the
  /// denormalized `phone` primary. De-duplicates by normalized key. Never
  /// throws — a corrupt JSON row just yields the `phone` fallback (or empty).
  List<ContactPhone> getContactPhones(DueContact contact) {
    final fromJson = ContactPhone.decode(contact.phones);
    if (fromJson.isNotEmpty) {
      return _dedupePhones(fromJson);
    }
    if (contact.phone != null && contact.phone!.isNotEmpty) {
      return [ContactPhone(number: contact.phone!)];
    }
    return const [];
  }

  List<ContactPhone> _dedupePhones(List<ContactPhone> phones) {
    final seen = <String>{};
    final out = <ContactPhone>[];
    for (final p in phones) {
      if (p.number.isEmpty || seen.contains(p.number)) continue;
      seen.add(p.number);
      out.add(p);
    }
    return out;
  }

  /// Find an existing contact that holds [normalizedPhone] — as its primary
  /// `phone` or anywhere in its `phones` list — excluding [excludeId]. Used by
  /// the import flow's dedup guard so the user can open the existing contact
  /// instead of creating a duplicate. Returns null if none match.
  ///
  /// `phones` is JSON, so we can't match it in SQL; we load the (small, local)
  /// contact set and match in Dart. The primary `phone` column is checked first
  /// as a fast path.
  Future<DueContact?> findContactByPhone(String normalizedPhone, {String? excludeId}) async {
    if (normalizedPhone.isEmpty) return null;
    // Fast path: primary phone column equality.
    final primaryQuery = _db.select(_db.dueContacts)
      ..where((c) => c.phone.equals(normalizedPhone));
    if (excludeId != null) {
      primaryQuery.where((c) => c.id.equals(excludeId).not());
    }
    final primaryMatch = await primaryQuery.getSingleOrNull();
    if (primaryMatch != null) return primaryMatch;

    // Slow path: scan the `phones` JSON of every other contact for a match.
    final all = await (_db.select(_db.dueContacts)).get();
    for (final c in all) {
      if (c.id == excludeId) continue;
      final nums = ContactPhone.decode(c.phones).map((e) => e.number).toSet();
      if (nums.contains(normalizedPhone)) return c;
    }
    return null;
  }

  /// Targeted update of just the cached photo path. The import flow writes the
  /// thumbnail to a temp file, creates the contact, then renames the file to a
  /// stable id-based path — this persists that final path without re-passing
  /// every other field through `updateContact`.
  Future<void> setContactPhotoPath(String id, String? photoPath) async {
    await (_db.update(_db.dueContacts)..where((c) => c.id.equals(id))).write(
      DueContactsCompanion(
        photoPath: Value(photoPath),
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
    // This will fail if there are entries or settlements (RESTRICT), which is
    // desired. The UI pre-counts via [countEntriesByContact] /
    // [countSettlementsByContact] and blocks with a clear message, but this
    // remains the safety net.
    await _db.duesDao.deleteContact(id);
  }

  /// Number of due entries bound to this contact. Used by the contact-delete
  /// guard so the user is told exactly how many records block deletion, rather
  /// than relying on a caught RESTRICT exception with a generic message.
  Future<int> countEntriesByContact(String id) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS cnt FROM due_entries WHERE contact_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    return (row.data['cnt'] as int?) ?? 0;
  }

  /// Number of settlements bound to this contact (same purpose as above; both
  /// `due_entries.contact_id` and `due_settlements.contact_id` are RESTRICT).
  Future<int> countSettlementsByContact(String id) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS cnt FROM due_settlements WHERE contact_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    return (row.data['cnt'] as int?) ?? 0;
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

  /// Re-dates a settlement — and its linked transaction, if any — to [date]
  /// (a day; the time component is dropped). Both `due_settlements.settled_date`
  /// and the linked `transactions.transaction_date` are written together in one
  /// transaction so the settlement record and its posting in reports stay in
  /// sync. Reports group on `transaction_date`, so this re-buckets the linked
  /// transaction into the right month/day. Used by the "edit settlement date"
  /// affordance so an old settlement logged on the wrong day can be moved
  /// without deleting and re-settling.
  Future<void> updateSettlementDate(String settlementId, DateTime date) async {
    final iso = DateTime(date.year, date.month, date.day).toIso8601String();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(_db.dueSettlements)
            ..where((t) => t.id.equals(settlementId)))
          .write(DueSettlementsCompanion(
        settledDate: Value(iso),
        updatedAt: Value(now),
      ));
      final s = await _db.duesDao.getSettlementById(settlementId);
      if (s != null && s.linkedTransactionId != null) {
        await (_db.update(_db.transactions)
              ..where((t) => t.id.equals(s.linkedTransactionId!)))
            .write(TransactionsCompanion(
          transactionDate: Value(iso),
          updatedAt: Value(now),
        ));
      }
    });
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
