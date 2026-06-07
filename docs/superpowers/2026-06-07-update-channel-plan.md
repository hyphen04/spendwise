# Implementation Plan: Update Channel Overhaul
**Spec:** `docs/superpowers/specs/2026-06-07-update-channel-design.md`  
**Date:** 2026-06-07

---

## Phase 0 — API Reference (Pre-verified)

### connectivity_plus v6.x
- Import: `package:connectivity_plus/connectivity_plus.dart`
- One-shot check: `await Connectivity().checkConnectivity()` → `List<ConnectivityResult>`
- Online check: `result.isNotEmpty && !result.contains(ConnectivityResult.none)`
- Requires `android.permission.ACCESS_NETWORK_STATE` in AndroidManifest.xml

### Kotlin MethodChannel (from flutter_local_notifications example + share_plus)
- Override `configureFlutterEngine(flutterEngine: FlutterEngine)` in `MainActivity`
- Call `super.configureFlutterEngine(flutterEngine)` first
- Create: `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result -> ... }`
- FileProvider: `FileProvider.getUriForFile(this@MainActivity, authority, file)`
- Error: `result.error("CODE", message, null)`
- Success: `result.success("launched")`
- Required imports: `android.content.Intent`, `androidx.core.content.FileProvider`, `io.flutter.embedding.engine.FlutterEngine`, `io.flutter.plugin.common.MethodChannel`, `java.io.File`

### Dart MethodChannel invocation
```dart
const _channel = MethodChannel('dev.kunj.spendwise/install');
await _channel.invokeMethod<String>('installApk', {'filePath': filePath});
```

### Riverpod StateProvider pattern (from `lib/state/prefs_providers.dart`)
```dart
final myProvider = StateProvider<MyType?>((ref) => null);
// override in ProviderScope:
myProvider.overrideWith((ref) => initialValue)
```

### StateNotifierProvider pattern (from existing prefs_providers.dart)
```dart
final myBoolProvider = StateNotifierProvider<MyNotifier, bool>(
    (ref) => MyNotifier(ref.watch(prefsServiceProvider)));

class MyNotifier extends StateNotifier<bool> {
  MyNotifier(this._prefs) : super(_prefs.myBool);
  final PrefsService _prefs;
  Future<void> set(bool v) async { await _prefs.setMyBool(v); state = v; }
}
```

---

## Phase 1 — Dependencies + Android Native

**Goal:** Add `connectivity_plus`, remove `open_file`, write `MainActivity.kt` MethodChannel, add network permission.

### Tasks

**1.1 — `pubspec.yaml`**
- Add `connectivity_plus: ^6.0.0` under `dependencies:`
- Remove `open_file: ^3.3.2` line entirely
- Run `flutter pub get`

**1.2 — `android/app/src/main/AndroidManifest.xml`**
- Add after the existing permissions block:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
  ```

**1.3 — `android/app/src/main/kotlin/dev/kunj/spendwise/MainActivity.kt`**

Replace entire file with:
```kotlin
package dev.kunj.spendwise

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val channel = "dev.kunj.spendwise/install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        try {
                            val filePath = call.argument<String>("filePath")
                                ?: throw IllegalArgumentException("filePath is required")
                            val file = File(filePath)
                            val uri = FileProvider.getUriForFile(
                                this@MainActivity,
                                "dev.kunj.spendwise.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                data = uri
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success("launched")
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

### Verification
- `grep -r "open_file" lib/ pubspec.yaml` → must return 0 results after Phase 2
- `grep "connectivity_plus" pubspec.yaml` → must find the entry
- `grep "ACCESS_NETWORK_STATE" android/app/src/main/AndroidManifest.xml` → must find it

---

## Phase 2 — UpdateService Rewrite

**Goal:** Replace `open_file` install with MethodChannel call; add `checkForUpdateIfDue()`.

### Reference files
- Current service: `lib/services/update_service.dart` (read in full before editing)
- Spec: `docs/superpowers/specs/2026-06-07-update-channel-design.md` § Architecture 1 & 2

### Tasks

**2.1 — Remove `open_file` from `update_service.dart`**
- Remove `import 'package:open_file/open_file.dart';` (and `ResultType` usage)
- Keep all other imports

**2.2 — Add MethodChannel constant**
At the top of `UpdateService` class body:
```dart
static const _installChannel = MethodChannel('dev.kunj.spendwise/install');
```
Add import: `import 'package:flutter/services.dart';`

**2.3 — Rewrite `installApk()`**
Replace the `OpenFile.open()` block (keep the permission check above it unchanged):
```dart
try {
  final r = await _installChannel.invokeMethod<String>(
    'installApk', {'filePath': filePath});
  if (r == 'launched') return InstallResult.launched;
  return InstallResult.error;
} on PlatformException catch (e) {
  debugPrint('installApk channel error: ${e.message}');
  return InstallResult.error;
}
```
Add import: `import 'package:flutter/foundation.dart';`

**2.4 — Add `checkForUpdateIfDue()` static method**

Add after `checkForUpdate()`:
```dart
/// Returns [UpdateInfo] if an update is available and the check is due,
/// null otherwise. Never throws — failures are swallowed.
static Future<UpdateInfo?> checkForUpdateIfDue(PrefsService prefs) async {
  try {
    if (!prefs.autoCheckUpdates) return null;
    final last = prefs.lastUpdateCheckMs;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 24).inMilliseconds) return null;

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity.isNotEmpty &&
        !connectivity.contains(ConnectivityResult.none);
    if (!isOnline) return null;

    final info = await checkForUpdate();
    await prefs.setLastUpdateCheckMs(now);
    return info;
  } catch (_) {
    return null;
  }
}
```
Add imports:
```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'prefs_service.dart';
```

### Verification
- `flutter analyze lib/services/update_service.dart` → 0 errors
- `grep "open_file\|OpenFile\|ResultType" lib/services/update_service.dart` → 0 results
- `grep "MethodChannel\|installApk\|checkForUpdateIfDue" lib/services/update_service.dart` → finds all three

---

## Phase 3 — Prefs + Providers

**Goal:** Add two new prefs keys, one Riverpod provider, and a new `pendingUpdateProvider` state file.

### Reference files
- Pattern: `lib/services/prefs_service.dart` (existing bool + int patterns)
- Pattern: `lib/state/prefs_providers.dart` (existing StateNotifierProvider pattern)

### Tasks

**3.1 — `lib/services/prefs_service.dart`**

Add at the end of the class (before closing `}`):
```dart
bool get autoCheckUpdates => _prefs.getBool('auto_check_updates') ?? true;
Future<void> setAutoCheckUpdates(bool v) =>
    _prefs.setBool('auto_check_updates', v);

int get lastUpdateCheckMs => _prefs.getInt('last_update_check_ms') ?? 0;
Future<void> setLastUpdateCheckMs(int v) =>
    _prefs.setInt('last_update_check_ms', v);
```

**3.2 — `lib/state/prefs_providers.dart`**

Add at the end of the file:
```dart
// ── Auto-check for updates ────────────────────────────────────────────────────

final autoCheckUpdatesProvider =
    StateNotifierProvider<AutoCheckUpdatesNotifier, bool>(
        (ref) => AutoCheckUpdatesNotifier(ref.watch(prefsServiceProvider)));

class AutoCheckUpdatesNotifier extends StateNotifier<bool> {
  AutoCheckUpdatesNotifier(this._prefs) : super(_prefs.autoCheckUpdates);
  final PrefsService _prefs;

  Future<void> set(bool v) async {
    await _prefs.setAutoCheckUpdates(v);
    state = v;
  }
}
```

**3.3 — Create `lib/state/update_provider.dart`**

New file:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';

final pendingUpdateProvider = StateProvider<UpdateInfo?>((ref) => null);
```

### Verification
- `flutter analyze lib/services/prefs_service.dart lib/state/prefs_providers.dart lib/state/update_provider.dart` → 0 errors
- `grep "autoCheckUpdates\|lastUpdateCheckMs" lib/services/prefs_service.dart` → finds both
- `grep "autoCheckUpdatesProvider\|pendingUpdateProvider" lib/state/` (recursive) → finds both

---

## Phase 4 — Startup + UI

**Goal:** Wire up startup check in `main.dart`, add `_UpdateBanner` to `HomeScreen`, add toggle to `SettingsScreen`.

### Reference files
- `lib/main.dart` — add startup check before `runApp`
- `lib/features/home/home_screen.dart` — add banner in CustomScrollView (read first)
- `lib/features/settings/settings_screen.dart` — add SwitchListTile (read About section first)

### Tasks

**4.1 — `lib/main.dart`**

Add imports:
```dart
import 'state/update_provider.dart';
```

After `await UpdateService.cleanupPendingApk();` and after `prefsService` is created, add:
```dart
UpdateInfo? pendingUpdate;
if (prefsService.autoCheckUpdates) {
  pendingUpdate = await UpdateService.checkForUpdateIfDue(prefsService);
}
```

In `ProviderScope` overrides, add:
```dart
pendingUpdateProvider.overrideWith((ref) => pendingUpdate),
```

**4.2 — `lib/features/home/home_screen.dart`**

Read the file first to find where the CustomScrollView slivers begin.

Add a new private widget `_UpdateBanner`:
```dart
class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner(this.info);
  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_outlined, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SpendWise v${info.version} available',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: cs.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _UpdateCheckDialog(
                currentVersion: info.version,
              ),
            ),
            child: const Text('Update'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: cs.onPrimaryContainer,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () =>
                ref.read(pendingUpdateProvider.notifier).state = null,
          ),
        ],
      ),
    );
  }
}
```

In the `build` method, read `pendingUpdateProvider` and insert the banner as a `SliverToBoxAdapter` at the top of the slivers list, before the existing first sliver:
```dart
final pendingUpdate = ref.watch(pendingUpdateProvider);
// ... in slivers list:
if (pendingUpdate != null)
  SliverToBoxAdapter(child: _UpdateBanner(pendingUpdate)),
```

Note: `_UpdateCheckDialog` is defined in `settings_screen.dart`. To avoid coupling, import it or extract it. Since it's a private class (`_`), it cannot be imported — move `_UpdateCheckDialog` and its `_UpdateState` enum to a shared file or make it public. See note below.

**Important:** `_UpdateCheckDialog` is currently private in `settings_screen.dart`. Move it to `lib/features/settings/update_check_dialog.dart` as a public `UpdateCheckDialog` (and `UpdateState` enum). Update the import in `settings_screen.dart`.

**4.3 — `lib/features/settings/settings_screen.dart`**

- Remove `import 'package:open_file/open_file.dart';` if present
- Add import for `update_check_dialog.dart` (after the move in 4.2)
- Add imports: `import '../../state/prefs_providers.dart';` (already present), `import '../../state/update_provider.dart';`
- In the About/Update section, add a `SwitchListTile` before the "Check for Update" tile:
```dart
SwitchListTile(
  secondary: const Icon(Icons.update_outlined),
  title: const Text('Auto-check for updates'),
  subtitle: const Text('Check on startup when connected'),
  value: ref.watch(autoCheckUpdatesProvider),
  onChanged: (v) => ref.read(autoCheckUpdatesProvider.notifier).set(v),
),
```

### Verification
- `flutter analyze lib/main.dart lib/features/home/home_screen.dart lib/features/settings/settings_screen.dart` → 0 errors
- `grep "pendingUpdateProvider" lib/features/home/home_screen.dart` → finds it
- `grep "autoCheckUpdatesProvider" lib/features/settings/settings_screen.dart` → finds it
- `grep "_UpdateCheckDialog\|open_file" lib/features/settings/settings_screen.dart` → 0 results (private class moved)

---

## Phase 5 — Final Verification

### Tasks

**5.1 — Full analyze**
```bash
flutter analyze
```
Expected: 0 errors, 0 warnings.

**5.2 — Grep guards (must all return 0 lines)**
```bash
grep -r "open_file\|OpenFile" lib/ pubspec.yaml
grep -r "ResultType" lib/
grep -r "_UpdateCheckDialog" lib/features/settings/settings_screen.dart
```

**5.3 — Grep presence checks (must find results)**
```bash
grep -r "install_apk\|installApk\|dev.kunj.spendwise/install" lib/
grep -r "checkForUpdateIfDue" lib/
grep -r "pendingUpdateProvider" lib/
grep -r "autoCheckUpdatesProvider" lib/
grep "connectivity_plus" pubspec.yaml
grep "ACCESS_NETWORK_STATE" android/app/src/main/AndroidManifest.xml
```

**5.4 — Build check**
```bash
flutter build apk --debug
```
Expected: builds without error.
