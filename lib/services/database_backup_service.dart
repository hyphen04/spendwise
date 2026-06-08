import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'prefs_service.dart';

class DatabaseBackupService {
  /// Creates a backup replica of the SQLite database before initializing it,
  /// ensuring the total size of all replicas does not exceed the user's quota.
  static Future<void> backupBeforeInit(PrefsService prefs) async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, 'expenses.db'));

      if (!await dbFile.exists()) {
        // Nothing to backup if it's a fresh install
        return;
      }

      final quotaMb = prefs.backupQuotaMb;
      final quotaBytes = quotaMb * 1024 * 1024;

      final backupsFolder = Directory(p.join(dbFolder.path, 'backups'));
      if (!await backupsFolder.exists()) {
        await backupsFolder.create(recursive: true);
      }

      final currentDbSize = await dbFile.length();
      
      // If the quota is 0 or somehow less than the db size, we can't even store one backup (unless it's set to "Unlimited").
      // We will define -1 as "Unlimited".
      if (quotaMb > 0 && currentDbSize > quotaBytes) {
        // Can't even fit the single new backup in the quota. We'll clear old ones and skip backup.
        await _clearAllBackups(backupsFolder);
        return;
      }

      // Read existing backups
      final backupFiles = backupsFolder
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList()
        ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync())); // Oldest first

      // Calculate current total size
      int totalBackupsSize = backupFiles.fold(0, (sum, file) => sum + file.lengthSync());

      // If we have a quota (not -1/Unlimited), enforce it
      if (quotaMb > 0) {
        while (backupFiles.isNotEmpty && (totalBackupsSize + currentDbSize) > quotaBytes) {
          final oldestFile = backupFiles.removeAt(0);
          final sizeToFree = oldestFile.lengthSync();
          await oldestFile.delete();
          totalBackupsSize -= sizeToFree;
          debugPrint('Deleted old replica: ${oldestFile.path}');
        }
      }

      // Create new backup
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newBackupFile = File(p.join(backupsFolder.path, 'replica_$timestamp.db'));
      await dbFile.copy(newBackupFile.path);
      
      debugPrint('Successfully created DB replica: ${newBackupFile.path}');

    } catch (e, st) {
      debugPrint('Failed to create DB replica: $e\n$st');
    }
  }

  static Future<void> _clearAllBackups(Directory backupsFolder) async {
    final backupFiles = backupsFolder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList();
    for (final f in backupFiles) {
      await f.delete();
    }
  }

  /// Gets a list of all backup replica files, sorted from newest to oldest.
  static Future<List<File>> getBackups() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final backupsFolder = Directory(p.join(dbFolder.path, 'backups'));
    if (!await backupsFolder.exists()) {
      return [];
    }
    final backupFiles = backupsFolder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())); // Newest first
    return backupFiles;
  }

  /// Restores a given backup file. Requires the app to restart afterwards.
  static Future<void> restoreBackup(File backupFile, {dynamic db}) async {
    if (db != null) {
      try {
        await db.close();
      } catch (e) {
        debugPrint('Error closing db before restore: $e');
      }
    }
    
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'expenses.db'));
    
    // Copy the backup replica over the active database file
    await backupFile.copy(dbFile.path);
  }

  /// Exports the raw 'expenses.db' file and the latest replica (if any) as a single ZIP file
  static Future<void> exportRawDatabaseZip() async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, 'expenses.db'));
      
      final filesToZip = <File>[];
      if (await dbFile.exists()) {
        filesToZip.add(dbFile);
      }

      final backups = await getBackups();
      if (backups.isNotEmpty) {
        filesToZip.add(backups.first); // latest replica
      }

      if (filesToZip.isEmpty) {
        debugPrint('No database files found to export.');
        return;
      }

      final encoder = ZipFileEncoder();
      final tempDir = await getTemporaryDirectory();
      final zipPath = p.join(tempDir.path, 'spendwise_raw_db_backup.zip');
      
      encoder.create(zipPath);
      for (final f in filesToZip) {
        encoder.addFile(f);
      }
      encoder.close();

      await Share.shareXFiles(
        [XFile(zipPath)],
        text: 'SpendWise Raw Database Backup',
      );
    } catch (e, st) {
      debugPrint('Error exporting raw database: $e\n$st');
    }
  }
}
