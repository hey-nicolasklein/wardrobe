import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the native session token in the Keychain/Keystore and keeps a copy
/// in memory so every API request can attach it synchronously.
class SessionStore {
  SessionStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'form_session_token';

  final FlutterSecureStorage _storage;
  String? _token;

  String? get token => _token;

  Future<void> load() async => _token = await _storage.read(key: _key);

  Future<void> save(String token) async {
    _token = token;
    await _storage.write(key: _key, value: token);
  }

  Future<void> clear() async {
    _token = null;
    await _storage.delete(key: _key);
  }
}
