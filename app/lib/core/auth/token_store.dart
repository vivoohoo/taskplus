import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the access and refresh tokens in the phone's secure storage (Keychain / Keystore).
abstract class TokenStore {
  Future<({String access, String refresh})?> read();
  Future<void> save(String access, String refresh);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<({String access, String refresh})?> read() async {
    final a = await _storage.read(key: 'access'), r = await _storage.read(key: 'refresh');
    return a == null || r == null ? null : (access: a, refresh: r);
  }

  @override
  Future<void> save(String access, String refresh) async {
    await _storage.write(key: 'access', value: access);
    await _storage.write(key: 'refresh', value: refresh);
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}

/// In memory, for tests.
class MemoryTokenStore implements TokenStore {
  ({String access, String refresh})? _t;
  @override
  Future<({String access, String refresh})?> read() async => _t;
  @override
  Future<void> save(String access, String refresh) async => _t = (access: access, refresh: refresh);
  @override
  Future<void> clear() async => _t = null;
}
