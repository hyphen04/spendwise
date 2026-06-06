import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'data/db/app_database.dart';
import 'state/database_provider.dart';
import 'state/prefs_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final sharedPrefs = await SharedPreferences.getInstance();
  final prefsService = PrefsService(sharedPrefs);

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        prefsServiceProvider.overrideWithValue(prefsService),
      ],
      child: const SpendWiseApp(),
    ),
  );
}
