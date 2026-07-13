import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/state/ai_providers.dart';
import 'package:spendwise/state/prefs_providers.dart';

/// Proves the "Share category & account names" toggle takes effect immediately
/// (without an app restart). Before the fix, [aiConfigProvider] read
/// `prefs.aiShareNames` through the immutable [prefsServiceProvider] and never
/// recomputed when the toggle flipped — so this test would fail on the old code.
void main() {
  late PrefsService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    final sp = await SharedPreferences.getInstance();
    prefs = PrefsService(sp);
  });

  test('flipping aiShareNamesProvider updates aiConfigProvider without restart',
      () async {
    final container = ProviderContainer(
      overrides: [prefsServiceProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // Default: anonymize (shareNames = false).
    expect(container.read(aiConfigProvider).shareNames, isFalse);

    // Flip the toggle (this is what the settings Switch.onChanged does, minus
    // the belt-and-suspenders invalidate).
    await container.read(aiShareNamesProvider.notifier).set(true);

    // The config provider must now reflect shareNames = true WITHOUT a restart
    // — i.e. it recomputed because it watches aiShareNamesProvider.
    expect(container.read(aiConfigProvider).shareNames, isTrue);

    // And flipping back works too.
    await container.read(aiShareNamesProvider.notifier).set(false);
    expect(container.read(aiConfigProvider).shareNames, isFalse);
  });
}