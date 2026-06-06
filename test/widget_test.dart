import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/app.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/services/prefs_service.dart';
import 'package:spendwise/state/database_provider.dart';
import 'package:spendwise/state/prefs_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // flutter_animate creates timers during initState; disable hot-reload
  // restart behaviour so FakeAsync doesn't choke in widget tests.
  setUpAll(() => Animate.restartOnHotReload = false);

  testWidgets('SpendWise v2 app launches without error',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final prefsService = PrefsService(prefs);
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          prefsServiceProvider.overrideWithValue(prefsService),
        ],
        child: const SpendWiseApp(),
      ),
    );
    // Drain all animation timers (flutter_animate uses delayed futures).
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(MaterialApp), findsOneWidget);
    await db.close();
  });
}
