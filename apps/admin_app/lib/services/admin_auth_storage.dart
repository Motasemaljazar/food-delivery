import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _kAdminKey = 'admin_api_key';

class AdminAuthStorage {
  AdminAuthStorage() : _storage = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;

  Future<String?> getAdminKey() => _storage.read(key: _kAdminKey);

  Future<void> setAdminKey(String key) => _storage.write(key: _kAdminKey, value: key);

  Future<void> clearAdminKey() => _storage.delete(key: _kAdminKey);
}
