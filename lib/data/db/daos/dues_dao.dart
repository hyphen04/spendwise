import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/due_contacts_table.dart';
import '../tables/due_entries_table.dart';
import '../tables/due_settlements_table.dart';
import '../tables/transactions_table.dart';

part 'dues_dao.g.dart';

class DueSettlementWithCount {
  final DueSettlement settlement;
  final int entryCount;
  DueSettlementWithCount(this.settlement, this.entryCount);
}

class DueEntryWithContact {
  final DueEntry entry;
  final DueContact contact;
  DueEntryWithContact(this.entry, this.contact);
}

@DriftAccessor(tables: [DueContacts, DueEntries, DueSettlements, Transactions])
class DuesDao extends DatabaseAccessor<AppDatabase> with _$DuesDaoMixin {
  DuesDao(super.db);

  // --- Contacts ---

  Stream<List<DueContact>> watchAllContacts() =>
      (select(dueContacts)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Future<void> upsertContact(DueContactsCompanion entry) =>
      into(dueContacts).insertOnConflictUpdate(entry);

  Future<void> deleteContact(String id) =>
      (delete(dueContacts)..where((c) => c.id.equals(id))).go();

  // --- Entries ---

  Stream<List<DueEntry>> watchUnsettledEntries(String contactId) =>
      (select(dueEntries)
            ..where((e) => e.contactId.equals(contactId) & e.isSettled.equals(false))
            ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]))
          .watch();

  Future<void> upsertEntry(DueEntriesCompanion entry) =>
      into(dueEntries).insertOnConflictUpdate(entry);

  Future<void> deleteEntry(String id) =>
      (delete(dueEntries)..where((e) => e.id.equals(id))).go();

  Future<List<DueEntryWithContact>> getAllEntriesWithContact() async {
    final query = select(dueEntries).join([
      innerJoin(dueContacts, dueContacts.id.equalsExp(dueEntries.contactId)),
    ])..orderBy([OrderingTerm.desc(dueEntries.entryDate)]);

    final rows = await query.get();
    return rows.map((row) {
      return DueEntryWithContact(
        row.readTable(dueEntries),
        row.readTable(dueContacts),
      );
    }).toList();
  }

  // --- Settlements ---

  Stream<List<DueSettlement>> watchSettlements(String contactId) =>
      (select(dueSettlements)
            ..where((s) => s.contactId.equals(contactId))
            ..orderBy([(s) => OrderingTerm.desc(s.settledDate)]))
          .watch();

  Stream<List<DueSettlementWithCount>> watchSettlementsWithCount(String contactId) {
    final countExp = dueEntries.id.count();
    final query = select(dueSettlements).join([
      leftOuterJoin(dueEntries, dueEntries.settlementId.equalsExp(dueSettlements.id)),
    ])
      ..where(dueSettlements.contactId.equals(contactId))
      ..orderBy([OrderingTerm.desc(dueSettlements.settledDate)])
      ..groupBy([dueSettlements.id]);

    query.addColumns([countExp]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return DueSettlementWithCount(
          row.readTable(dueSettlements),
          row.read(countExp) ?? 0,
        );
      }).toList();
    });
  }

  Future<DueSettlement?> getSettlementForTransaction(String transactionId) async {
    return (select(dueSettlements)..where((s) => s.linkedTransactionId.equals(transactionId))).getSingleOrNull();
  }

  Future<DueSettlement?> getSettlementById(String settlementId) async {
    return (select(dueSettlements)..where((s) => s.id.equals(settlementId))).getSingleOrNull();
  }

  Future<void> undoSettlement(String settlementId) async {
    return transaction(() async {
      await (update(dueEntries)..where((e) => e.settlementId.equals(settlementId))).write(
        DueEntriesCompanion(
          isSettled: const Value(false),
          settlementId: const Value(null),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await (delete(dueSettlements)..where((s) => s.id.equals(settlementId))).go();
    });
  }

  Future<List<DueEntry>> getEntriesForSettlement(String settlementId) async {
    return (select(dueEntries)..where((e) => e.settlementId.equals(settlementId))).get();
  }

  // --- Aggregates ---

  Future<double> getContactBalance(String contactId) async {
    final entries = await (select(dueEntries)
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
    return balance;
  }

  Future<Map<String, double>> getAllContactBalances() async {
    final entries = await (select(dueEntries)..where((e) => e.isSettled.equals(false))).get();
    
    final Map<String, double> balances = {};
    for (final e in entries) {
      final amt = e.direction == 'receivable' ? e.amount : -e.amount;
      balances[e.contactId] = (balances[e.contactId] ?? 0) + amt;
    }
    return balances;
  }

  Future<(int, double)> getMonthlyVendorStats(String contactId, int year, int month) async {
    final from = DateTime(year, month).toIso8601String();
    final to = DateTime(year, month + 1).toIso8601String();
    
    final entries = await (select(dueEntries)
          ..where((e) => 
              e.contactId.equals(contactId) & 
              e.entryDate.isBiggerOrEqualValue(from) &
              e.entryDate.isSmallerThanValue(to)))
        .get();
        
    double total = 0;
    for (final e in entries) {
      total += e.amount;
    }
    return (entries.length, total);
  }

  // --- Transactions ---

  Future<void> settleEntries({
    required String contactId,
    required List<String> entryIds,
    required DueSettlementsCompanion settlement,
    TransactionsCompanion? linkedTransaction,
  }) async {
    return transaction(() async {
      String? linkedTxId;
      if (linkedTransaction != null) {
        linkedTxId = linkedTransaction.id.value;
        await into(transactions).insert(linkedTransaction);
      }

      final actualSettlement = settlement.copyWith(
        linkedTransactionId: Value(linkedTxId),
      );
      final settlementId = actualSettlement.id.value;
      await into(dueSettlements).insert(actualSettlement);

      await (update(dueEntries)..where((e) => e.id.isIn(entryIds))).write(
        DueEntriesCompanion(
          isSettled: const Value(true),
          settlementId: Value(settlementId),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    });
  }
}
