import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/db/app_database.dart';

class DuesExportService {
  static Future<void> exportToCsv(AppDatabase db) async {
    final contacts = await (db.select(db.dueContacts)..orderBy([(c) => OrderingTerm.asc(c.name)])).get();
    
    final rows = <List<String>>[
      ['Contact Name', 'Type', 'Entry Date', 'Amount', 'Direction', 'Meal Slot', 'Note', 'Status', 'Settled Date'],
    ];

    for (final c in contacts) {
      final entries = await (db.select(db.dueEntries)..where((e) => e.contactId.equals(c.id))).get();
      for (final e in entries) {
        String settledDateStr = '';
        if (e.isSettled && e.settlementId != null) {
          final settlement = await (db.select(db.dueSettlements)..where((s) => s.id.equals(e.settlementId!))).getSingleOrNull();
          if (settlement != null) {
            settledDateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(settlement.settledDate));
          }
        }

        rows.add([
          c.name,
          c.type,
          DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(e.entryDate)),
          e.amount.toString(),
          e.direction,
          e.mealSlot ?? '',
          e.note,
          e.isSettled ? 'Settled' : 'Unsettled',
          settledDateStr,
        ]);
      }
    }

    final csvData = const ListToCsvConverter().convert(rows);
    
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/spendwise_dues_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csvData);
    
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'SpendWise Dues Export',
      ),
    );
  }
}
