import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _pinKey = 'app_pin';
  static const _llmKey = 'llm_api_key';

  static Future<void> savePin(String pin) =>
      _storage.write(key: _pinKey, value: pin);

  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    return stored == pin;
  }

  static Future<bool> hasPin() =>
      _storage.containsKey(key: _pinKey);

  static Future<void> clearPin() => _storage.delete(key: _pinKey);

  // ── AI Copilot API key ──────────────────────────────────────────────────
  //
  // The user-supplied LLM API key. Stored in secure storage (not prefs) so it
  // is never written to SharedPreferences and can never leak into a backup or
  // JSON export. The user supplies their own key and uses AI at their own risk;
  // the app never bundles a key or sends data to a third party without it.

  static Future<void> saveLlmKey(String key) =>
      _storage.write(key: _llmKey, value: key);

  static Future<String?> readLlmKey() => _storage.read(key: _llmKey);

  static Future<bool> hasLlmKey() => _storage.containsKey(key: _llmKey);

  static Future<void> clearLlmKey() => _storage.delete(key: _llmKey);
}
