import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/db/app_database.dart';

class RawDbImporter {
  static Future<void> importData(AppDatabase mainDb, String zipPath) async {
    final tempDir = await getTemporaryDirectory();
    final extractPath = p.join(tempDir.path, 'spendwise_raw_db_extract_${DateTime.now().millisecondsSinceEpoch}');
    
    final extractDir = Directory(extractPath);
    await extractDir.create(recursive: true);

    try {
      // 1. Extract zip
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File(p.join(extractDir.path, filename))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        }
      }

      // 2. Find the .db file (prefer replica if multiple, or expenses.db)
      final files = extractDir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList();
      if (files.isEmpty) {
        throw Exception('No SQLite .db file found in the zip.');
      }

      // Sort so replica (newest) might be first, though mostly there's just one or two
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final targetDbFile = files.first;

      // 3. Connect temporary AppDatabase
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final tempExecutor = NativeDatabase(targetDbFile);
      final tempDb = AppDatabase(tempExecutor);

      try {
        // We will trigger a query to ensure migrations run if it's an older db
        await tempDb.customSelect('SELECT 1').get();

        // 4. Fetch all data
        final accounts = await tempDb.select(tempDb.accounts).get();
        final categories = await tempDb.select(tempDb.categories).get();
        final modes = await tempDb.select(tempDb.modes).get();
        final tags = await tempDb.select(tempDb.tags).get();
        final transactions = await tempDb.select(tempDb.transactions).get();
        final transactionTags = await tempDb.select(tempDb.transactionTags).get();
        final budgets = await tempDb.select(tempDb.budgets).get();
        final dueContacts = await tempDb.select(tempDb.dueContacts).get();
        final dueEntries = await tempDb.select(tempDb.dueEntries).get();
        final dueSettlements = await tempDb.select(tempDb.dueSettlements).get();

        // 5. Upsert into main DB
        await mainDb.transaction(() async {
          // Delete all current data first to prevent duplicates
          await mainDb.delete(mainDb.transactionTags).go();
          await mainDb.delete(mainDb.transactions).go();
          await mainDb.delete(mainDb.dueEntries).go();
          await mainDb.delete(mainDb.dueSettlements).go();
          await mainDb.delete(mainDb.dueContacts).go();
          await mainDb.delete(mainDb.budgets).go();
          await mainDb.delete(mainDb.accounts).go();
          await mainDb.delete(mainDb.categories).go();
          await mainDb.delete(mainDb.modes).go();
          await mainDb.delete(mainDb.tags).go();

          for (final row in accounts) {
            await mainDb.into(mainDb.accounts).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in categories) {
            await mainDb.into(mainDb.categories).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in modes) {
            await mainDb.into(mainDb.modes).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in tags) {
            await mainDb.into(mainDb.tags).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in budgets) {
            await mainDb.into(mainDb.budgets).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in dueContacts) {
            await mainDb.into(mainDb.dueContacts).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in transactions) {
            await mainDb.into(mainDb.transactions).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in transactionTags) {
            await mainDb.into(mainDb.transactionTags).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in dueEntries) {
            await mainDb.into(mainDb.dueEntries).insert(row, mode: InsertMode.insertOrReplace);
          }
          for (final row in dueSettlements) {
            await mainDb.into(mainDb.dueSettlements).insert(row, mode: InsertMode.insertOrReplace);
          }
        });

      } finally {
        await tempDb.close();
      }

    } finally {
      // Cleanup
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
    }
  }
}
