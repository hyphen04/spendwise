import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_providers.dart';
import 'prefs_providers.dart';

/// Master app mode. Offline (the default) hides every internet-dependent
/// feature (AI Copilot, update checker, feedback) and keeps the app fully
/// on-device. Online restores the full app. Persisted as the enum name in
/// SharedPreferences (`app_mode`).
enum AppMode { online, offline }

final appModeProvider =
    StateNotifierProvider<AppModeNotifier, AppMode>(
        (ref) => AppModeNotifier(ref.watch(prefsServiceProvider)));

class AppModeNotifier extends StateNotifier<AppMode> {
  AppModeNotifier(this._prefs)
      : super(_prefs.appMode == 'online' ? AppMode.online : AppMode.offline);
  final PrefsService _prefs;

  Future<void> set(AppMode mode) async {
    await _prefs.setAppMode(mode.name);
    state = mode;
  }
}

/// `true` only in Online mode — the single gate every internet-dependent entry
/// point must check. When false, AI/update/feedback UI is hidden and online
/// operations are skipped.
final isOnlineProvider = Provider<bool>(
    (ref) => ref.watch(appModeProvider) == AppMode.online);

/// Effective AI enablement = the user opted into AI Copilot **and** the app is
/// in Online mode. Replaces bare [aiEnabledProvider] at every AI show/hide and
/// can-use call site, so Offline hides AI even when the user previously enabled
/// it. The stored `aiEnabled` value is left untouched (dormant) and resumes
/// exactly as-is when the user switches back to Online.
final aiEffectiveEnabledProvider = Provider<bool>(
    (ref) => ref.watch(isOnlineProvider) && ref.watch(aiEnabledProvider));