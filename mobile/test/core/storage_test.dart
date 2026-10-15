import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TokenStorage Tests', () {
    test('initially has no token', () async {
      final storage = TokenStorage();
      expect(await storage.getToken(), isNull);
      expect(await storage.hasToken(), isFalse);
    });

    test('saveToken persists token and notifies listeners', () async {
      final storage = TokenStorage();
      var notified = false;
      storage.addListener(() => notified = true);

      await storage.saveToken('auth_token_xyz');

      expect(notified, isTrue);
      expect(await storage.getToken(), 'auth_token_xyz');
      expect(await storage.hasToken(), isTrue);
    });

    test('deleteToken wipes token and notifies listeners', () async {
      final storage = TokenStorage();
      await storage.saveToken('auth_token_xyz');
      expect(await storage.hasToken(), isTrue);

      var notified = false;
      storage.addListener(() => notified = true);

      await storage.deleteToken();

      expect(notified, isTrue);
      expect(await storage.getToken(), isNull);
      expect(await storage.hasToken(), isFalse);
    });

    test('clearCache forces reload from underlying secure storage', () async {
      final storage = TokenStorage();
      await storage.saveToken('cached_token');

      // Clear in-memory cache
      storage.clearCache();

      // Next read should still retrieve the persisted value
      expect(await storage.getToken(), 'cached_token');
    });
  });
}
