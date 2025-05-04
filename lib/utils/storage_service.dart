import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  // Private constructor
  SecureStorageService._internal() : _storage = const FlutterSecureStorage();

  // The single instance
  static final SecureStorageService _instance =
      SecureStorageService._internal();

  // Factory returns the same instance every time
  factory SecureStorageService() => _instance;

  final FlutterSecureStorage _storage;

  Future<String?> readValue(String key) => _storage.read(key: key);

  Future<void> saveValue(String key, String value) =>
      _storage.write(key: key, value: value);
}
