import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'app/recovery_app.dart';
import 'data/db/app_database.dart';
import 'services/database_backup_service.dart';
import 'services/update_service.dart';
import 'state/database_provider.dart';
import 'state/prefs_providers.dart';
import 'state/update_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Delete any leftover APK from a previous in-app update installation
  await UpdateService.cleanupPendingApk();

  final sharedPrefs = await SharedPreferences.getInstance();
  final prefsService = PrefsService(sharedPrefs);

  final db = AppDatabase();

  bool isDbCorrupted = false;
  try {
    // Ping the database to force Drift to open the SQLite file and check integrity.
    // If it's malformed, this will throw an exception.
    await db.customSelect('SELECT 1').get();
  } catch (e, st) {
    debugPrint('Database corruption detected: $e\n$st');
    isDbCorrupted = true;
  }

  if (isDbCorrupted) {
    runApp(const RecoveryApp());
    return;
  }

  // Take a rolling replica backup ONLY if the DB is healthy
  await DatabaseBackupService.backupBeforeInit(prefsService);

  UpdateInfo? pendingUpdate;
  if (prefsService.autoCheckUpdates) {
    pendingUpdate = await UpdateService.checkForUpdateIfDue(prefsService);
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        prefsServiceProvider.overrideWithValue(prefsService),
        pendingUpdateProvider.overrideWith((ref) => pendingUpdate),
      ],
      child: const SpendWiseApp(),
    ),
  );
}
