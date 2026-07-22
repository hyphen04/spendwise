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

  bool get hideNetWorth => _prefs.getBool('hide_net_worth') ?? true;
  Future<void> setHideNetWorth(bool v) => _prefs.setBool('hide_net_worth', v);

  int get themeSeedColor =>
      _prefs.getInt('theme_seed_color') ?? 0xFF0A0A0A; // Default to Black
  Future<void> setThemeSeedColor(int v) => _prefs.setInt('theme_seed_color', v);

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

  int get backupQuotaMb => _prefs.getInt('backup_quota_mb') ?? 10;
  Future<void> setBackupQuotaMb(int v) => _prefs.setInt('backup_quota_mb', v);

  bool get showQuickDuesWidget => _prefs.getBool('show_quick_dues') ?? true;
  Future<void> setShowQuickDuesWidget(bool v) =>
      _prefs.setBool('show_quick_dues', v);

  /// Whether the user has enabled device-contact access for the Dues import
  /// flow. This is a *user intent* toggle (Settings → Contact Access): it gates
  /// whether the "Import from phone" affordance is offered. The actual OS
  /// permission is still requested at pick time. Contacts are read on-device
  /// only and never uploaded.
  bool get contactAccess => _prefs.getBool('contact_access') ?? false;
  Future<void> setContactAccess(bool v) => _prefs.setBool('contact_access', v);

  // ── App Mode (master Offline/Online kill switch). Offline (default) hides
  // every internet-dependent feature — AI Copilot, the GitHub update checker,
  // and feedback submission — and keeps the app fully on-device. Online
  // restores the full app with the existing sub-toggles intact. Stored as the
  // enum name ('online' | 'offline'); see AppMode in app_mode_providers.dart.
  String get appMode => _prefs.getString('app_mode') ?? 'offline';
  Future<void> setAppMode(String v) => _prefs.setString('app_mode', v);

  // ── AI Copilot (non-secret config; the API key is NOT stored here — it
  // lives in SecureStorageService). AI is entirely opt-in and off by default.
  bool get aiEnabled => _prefs.getBool('ai_enabled') ?? false;
  Future<void> setAiEnabled(bool v) => _prefs.setBool('ai_enabled', v);

  /// Provider preset id: 'openai' | 'openrouter' | 'groq' | 'gemini' | 'custom'.
  String get aiProvider => _prefs.getString('ai_provider') ?? 'openai';
  Future<void> setAiProvider(String v) => _prefs.setString('ai_provider', v);

  /// Optional base-URL override; null/empty → use the preset default.
  String? get aiBaseUrl => _prefs.getString('ai_base_url');
  Future<void> setAiBaseUrl(String? v) async {
    if (v == null || v.isEmpty) {
      await _prefs.remove('ai_base_url');
    } else {
      await _prefs.setString('ai_base_url', v);
    }
  }

  /// Optional model override; null/empty → use the preset default.
  String? get aiModel => _prefs.getString('ai_model');
  Future<void> setAiModel(String? v) async {
    if (v == null || v.isEmpty) {
      await _prefs.remove('ai_model');
    } else {
      await _prefs.setString('ai_model', v);
    }
  }

  /// Whether the user allows category/account/mode names to be sent to the LLM
  /// (anonymized rank keys are sent otherwise). Notes, contact names, phone
  /// numbers and photos are ALWAYS stripped regardless of this toggle.
  bool get aiShareNames => _prefs.getBool('ai_share_names') ?? false;
  Future<void> setAiShareNames(bool v) => _prefs.setBool('ai_share_names', v);

  /// Whether the AI Report may propose its own chart layout (the LLM emits a
  /// chart spec; the app executes it on-device). Off by default — the report
  /// uses a safe fixed default spec, so charts always render even with AI off.
  /// The LLM still only sees schema metadata + opaque labels; it never sees raw
  /// rows or real amounts.
  bool get aiSpecEnabled => _prefs.getBool('ai_spec_enabled') ?? false;
  Future<void> setAiSpecEnabled(bool v) => _prefs.setBool('ai_spec_enabled', v);

  /// Whether the AI may author read-only SQL queries against the user's data
  /// (the opt-in `customSql` provider). Off by default. Even when on, queries
  /// run through the [SqlGuard] safety pipeline: single-statement, SELECT-only,
  /// blocked keywords/tables/columns, auto-LIMIT, timeout. Results never leave
  /// the device. Requires [aiSpecEnabled] to be meaningful.
  bool get aiCustomSql => _prefs.getBool('ai_custom_sql') ?? false;
  Future<void> setAiCustomSql(bool v) => _prefs.setBool('ai_custom_sql', v);

  /// Whether the AI Copilot chat may call on-device lookup tools to answer
  /// questions (any category, any date range, filtered totals, goal status).
  /// On by default — tools return aggregates only (no rows, notes, contacts, or
  /// real names unless `aiShareNames` is also on). When off, the chat uses a
  /// static snapshot only.
  bool get aiToolCalling => _prefs.getBool('ai_tool_calling') ?? true;
  Future<void> setAiToolCalling(bool v) => _prefs.setBool('ai_tool_calling', v);
}
