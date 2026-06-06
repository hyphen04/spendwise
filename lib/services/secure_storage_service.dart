import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _pinKey = 'app_pin';

  static Future<void> savePin(String pin) =>
      _storage.write(key: _pinKey, value: pin);

  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    return stored == pin;
  }

  static Future<bool> hasPin() =>
      _storage.containsKey(key: _pinKey);

  static Future<void> clearPin() => _storage.delete(key: _pinKey);
}
