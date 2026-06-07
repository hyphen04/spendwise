import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  PrefsService(this._prefs);
  final SharedPreferences _prefs;

  ThemeMode get themeMode => switch (_prefs.getString('theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  Future<void> setThemeMode(ThemeMode m) =>
      _prefs.setString('theme_mode', m.name);

  bool get oledDark => _prefs.getBool('oled_dark') ?? false;
  Future<void> setOledDark(bool v) => _prefs.setBool('oled_dark', v);

  bool get lockEnabled => _prefs.getBool('lock_enabled') ?? false;
  Future<void> setLockEnabled(bool v) => _prefs.setBool('lock_enabled', v);

  int get lockTimeoutSeconds => _prefs.getInt('lock_timeout') ?? 30;
  Future<void> setLockTimeout(int v) => _prefs.setInt('lock_timeout', v);

  bool get biometricEnabled => _prefs.getBool('biometric_enabled') ?? true;
  Future<void> setBiometricEnabled(bool v) =>
      _prefs.setBool('biometric_enabled', v);

  bool get isFirstRun => _prefs.getBool('first_run') ?? true;
  Future<void> completeFirstRun() => _prefs.setBool('first_run', false);

  String? get defaultAccountId => _prefs.getString('default_account_id');
  Future<void> setDefaultAccountId(String? id) async {
    if (id == null) {
      await _prefs.remove('default_account_id');
    } else {
      await _prefs.setString('default_account_id', id);
    }
  }

  String? get defaultModeId => _prefs.getString('default_mode_id');
  Future<void> setDefaultModeId(String? id) async {
    if (id == null) {
      await _prefs.remove('default_mode_id');
    } else {
      await _prefs.setString('default_mode_id', id);
    }
  }

  bool get autoCheckUpdates => _prefs.getBool('auto_check_updates') ?? true;
  Future<void> setAutoCheckUpdates(bool v) =>
      _prefs.setBool('auto_check_updates', v);

  int get lastUpdateCheckMs => _prefs.getInt('last_update_check_ms') ?? 0;
  Future<void> setLastUpdateCheckMs(int v) =>
      _prefs.setInt('last_update_check_ms', v);

}
