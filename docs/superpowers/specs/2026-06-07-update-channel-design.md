# Update Channel Overhaul — Design Spec
**Date:** 2026-06-07  
**Status:** Approved

---

## Problem

The current in-app update flow has two issues:
1. Tapping "Install Now" closes the dialog but the system package installer never appears. Root cause: the `open_file` package uses `Intent.ACTION_VIEW` with the APK MIME type, which on many OEM ROMs (MIUI, OneUI, ColorOS) triggers a file chooser or is silently intercepted instead of directly launching the package installer.
2. No auto-check on startup — users must manually tap "Check for Update" in Settings to discover new versions.

---

## Solution Overview

1. **Fix install**: Replace `open_file` APK launch with a native Kotlin `MethodChannel` that uses `Intent.ACTION_INSTALL_PACKAGE` + the app's existing `FileProvider`. This is the standard approach used by open-source Flutter apps (Droid-ify, Obtainium, etc.).
2. **Auto-check**: On app startup, if `autoCheckUpdates` pref is `true` and the last check was >24h ago and connectivity is available, silently check GitHub. If an update is found, show a non-intrusive banner on the HomeScreen.
3. **Toggle**: Add a "Auto-check for updates" switch in Settings under the About section.

---

## Architecture

### 1. Native Install — `MainActivity.kt`

Add a `MethodChannel("dev.kunj.spendwise/install")` with one handler: `installApk`.

```kotlin
val file = File(filePath)
val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
    data = uri
    flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK
}
startActivity(intent)
result.success("launched")
```

The existing `file_paths.xml` already maps `cache-path / apk_downloads/` which is where `UpdateService.downloadApk()` saves the APK — no manifest changes needed.

**Dialog behavior on `launched`:** Instead of immediately calling `Navigator.pop()`, the dialog transitions to a brief "Opening installer…" state for ~1 second, then pops. This ensures the system installer has time to come to the foreground before the dialog disappears.

### 2. `UpdateService` changes

- Remove `open_file` import and `OpenFile.open()` call from `installApk()`.
- Replace with a `MethodChannel` invocation of `installApk` on the native side.
- Add `checkForUpdateIfDue()` static method:
  - Reads `lastUpdateCheckMs` from prefs; returns `null` immediately if last check < 24h ago.
  - Checks connectivity via `connectivity_plus`; returns `null` if offline.
  - Calls `checkForUpdate()`, writes current timestamp to prefs, returns `UpdateInfo?`.

### 3. Prefs

New keys in `PrefsService`:
- `auto_check_updates` (bool, default `true`)
- `last_update_check_ms` (int, default 0)

New Riverpod provider in `prefs_providers.dart`:
- `autoCheckUpdatesProvider` — `StateNotifierProvider<AutoCheckUpdatesNotifier, bool>`

### 4. Update State

New file `lib/state/update_provider.dart`:
- `pendingUpdateProvider` — `StateProvider<UpdateInfo?>`(initial: `null`)

### 5. Startup flow — `main.dart`

```dart
UpdateInfo? pendingUpdate;
final prefs = PrefsService(sharedPrefs);
if (prefs.autoCheckUpdates) {
  pendingUpdate = await UpdateService.checkForUpdateIfDue(prefs);
}

runApp(ProviderScope(
  overrides: [
    ...
    pendingUpdateProvider.overrideWith((_) => pendingUpdate),
  ],
  child: const SpendWiseApp(),
));
```

### 6. Update Banner — `HomeScreen`

At the top of the `CustomScrollView` (before the greeting sliver), conditionally render an `_UpdateBanner` widget when `ref.watch(pendingUpdateProvider) != null`.

The banner:
- Single-row card: "SpendWise vX.X.X available" + "Update" button
- "Update" button opens `_UpdateCheckDialog` (existing dialog, reused as-is)
- An "×" dismiss button sets `pendingUpdateProvider` to `null` for the session (does not persist)
- Styled to match the app's card aesthetic (surfaceContainer background, rounded corners)

### 7. Settings Toggle

Under the existing "About" section in `settings_screen.dart`, add a `SwitchListTile`:
- Title: "Auto-check for updates"
- Subtitle: "Check on startup when connected"
- Reads/writes `autoCheckUpdatesProvider`

---

## Dependencies

| Package | Change |
|---|---|
| `connectivity_plus: ^6.0.0` | Add |
| `open_file` | Remove |

The `permission_handler` integration for `REQUEST_INSTALL_PACKAGES` is unchanged — the permission check and "Allow from this source" settings redirect stay exactly as-is.

---

## Files Changed

| File | Change |
|---|---|
| `android/app/src/main/kotlin/dev/kunj/spendwise/MainActivity.kt` | Add `install_apk` MethodChannel |
| `lib/services/update_service.dart` | Replace `OpenFile` with channel; add `checkForUpdateIfDue()` |
| `lib/services/prefs_service.dart` | Add `autoCheckUpdates`, `lastUpdateCheckMs` |
| `lib/state/prefs_providers.dart` | Add `autoCheckUpdatesProvider` |
| `lib/state/update_provider.dart` | New file — `pendingUpdateProvider` |
| `lib/main.dart` | Startup check + provider override |
| `lib/features/home/home_screen.dart` | Add `_UpdateBanner` |
| `lib/features/settings/settings_screen.dart` | Add toggle; remove `open_file` import |
| `pubspec.yaml` | Add `connectivity_plus`; remove `open_file` |

---

## Error Handling

- `checkForUpdateIfDue()` catches all exceptions and returns `null` — startup must never throw.
- `installApk()` MethodChannel: wraps `startActivity` in try/catch; returns `"error"` string on failure, which maps to `InstallResult.error`.
- If `connectivity_plus` throws (rare, some devices), treat as offline.

---

## Explicitly Out of Scope

- Silent/background install (requires system signature permission — not available to sideloaded apps)
- Delta/incremental updates
- iOS support (APK install is Android-only; auto-check and banner work on both platforms but install is gated on `Platform.isAndroid`)
