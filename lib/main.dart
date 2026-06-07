import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'data/db/app_database.dart';
import 'services/update_service.dart';
import 'state/database_provider.dart';
import 'state/prefs_providers.dart';
import 'state/update_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Delete any leftover APK from a previous in-app update installation
  await UpdateService.cleanupPendingApk();

  final db = AppDatabase();
  final sharedPrefs = await SharedPreferences.getInstance();
  final prefsService = PrefsService(sharedPrefs);

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
