import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/prefs_service.dart';

// re-export for convenience
export '../services/prefs_service.dart' show PrefsService;

final prefsServiceProvider = Provider<PrefsService>(
    (_) => throw UnimplementedError('Override prefsServiceProvider'));

// ── Theme Mode ──────────────────────────────────────────────────────────────

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
        (ref) => ThemeModeNotifier(ref.watch(prefsServiceProvider)));

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(_prefs.themeMode);
  final PrefsService _prefs;

  Future<void> set(ThemeMode mode) async {
    await _prefs.setThemeMode(mode);
    state = mode;
  }
}

// ── OLED Dark ────────────────────────────────────────────────────────────────

final oledDarkProvider =
    StateNotifierProvider<OledDarkNotifier, bool>(
        (ref) => OledDarkNotifier(ref.watch(prefsServiceProvider)));

class OledDarkNotifier extends StateNotifier<bool> {
  OledDarkNotifier(this._prefs) : super(_prefs.oledDark);
  final PrefsService _prefs;

  Future<void> set(bool v) async {
    await _prefs.setOledDark(v);
    state = v;
  }
}

// ── App Lock ─────────────────────────────────────────────────────────────────

final lockEnabledProvider =
    StateNotifierProvider<LockEnabledNotifier, bool>(
        (ref) => LockEnabledNotifier(ref.watch(prefsServiceProvider)));

class LockEnabledNotifier extends StateNotifier<bool> {
  LockEnabledNotifier(this._prefs) : super(_prefs.lockEnabled);
  final PrefsService _prefs;

  Future<void> set(bool v) async {
    await _prefs.setLockEnabled(v);
    state = v;
  }
}

final biometricEnabledProvider =
    StateNotifierProvider<BiometricEnabledNotifier, bool>(
        (ref) => BiometricEnabledNotifier(ref.watch(prefsServiceProvider)));

class BiometricEnabledNotifier extends StateNotifier<bool> {
  BiometricEnabledNotifier(this._prefs) : super(_prefs.biometricEnabled);
  final PrefsService _prefs;

  Future<void> set(bool v) async {
    await _prefs.setBiometricEnabled(v);
    state = v;
  }
}

// ── Default Account ──────────────────────────────────────────────────────────

final defaultAccountIdProvider =
    StateNotifierProvider<DefaultAccountIdNotifier, String?>(
        (ref) => DefaultAccountIdNotifier(ref.watch(prefsServiceProvider)));

class DefaultAccountIdNotifier extends StateNotifier<String?> {
  DefaultAccountIdNotifier(this._prefs) : super(_prefs.defaultAccountId);
  final PrefsService _prefs;

  Future<void> set(String? id) async {
    await _prefs.setDefaultAccountId(id);
    state = id;
  }
}

// ── Default Mode ─────────────────────────────────────────────────────────────

final defaultModeIdProvider =
    StateNotifierProvider<DefaultModeIdNotifier, String?>(
        (ref) => DefaultModeIdNotifier(ref.watch(prefsServiceProvider)));

class DefaultModeIdNotifier extends StateNotifier<String?> {
  DefaultModeIdNotifier(this._prefs) : super(_prefs.defaultModeId);
  final PrefsService _prefs;

  Future<void> set(String? id) async {
    await _prefs.setDefaultModeId(id);
    state = id;
  }
}

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

