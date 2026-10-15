import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Riverpod provider for [TokenStorage].
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  final storage = TokenStorage();
  ref.onDispose(storage.dispose);
  return storage;
});

/// Secure storage manager for authentication tokens.
/// Extends [ChangeNotifier] so router guards or UI components can reactively respond to token changes.
class TokenStorage extends ChangeNotifier {
  final FlutterSecureStorage _storage;
  static const String _tokenKey = 'pair_auth_token';
  String? _cachedToken;
  bool _initialized = false;

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Persists the auth token into secure storage and notifies listeners.
  Future<void> saveToken(String token) async {
    _cachedToken = token;
    _initialized = true;
    await _storage.write(key: _tokenKey, value: token);
    notifyListeners();
  }

  /// Retrieves the auth token from cache or secure storage.
  Future<String?> getToken() async {
    if (_initialized) {
      return _cachedToken;
    }
    _cachedToken = await _storage.read(key: _tokenKey);
    _initialized = true;
    return _cachedToken;
  }

  /// Returns true if a valid non-empty auth token is present.
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Deletes the auth token from secure storage and clears cache, then notifies listeners.
  Future<void> deleteToken() async {
    _cachedToken = null;
    _initialized = true;
    await _storage.delete(key: _tokenKey);
    notifyListeners();
  }

  /// Clears in-memory cache, forcing next read from secure storage.
  void clearCache() {
    _cachedToken = null;
    _initialized = false;
  }
}
