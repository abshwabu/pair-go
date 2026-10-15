import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/goals/models/goal_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late TokenStorage tokenStorage;
  late ApiClient apiClient;

  setUp(() {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    tokenStorage = TokenStorage();
    apiClient = ApiClient(
      tokenStorage: tokenStorage,
      baseUrl: 'http://localhost:8085/api/v1',
    );
  });

  group('Live Go Backend End-to-End Integration', () {
    test('Full onboarding flow against live Go backend', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'e2e_user_$uniqueSuffix@pair.test';
      final testPassword = 'StrongPassword123!';

      // 1. Register new user
      final registerRes = await apiClient.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'name': 'E2E Tester',
          'email': testEmail,
          'password': testPassword,
          'timezone': 'UTC',
        },
      );

      expect(registerRes.data['token'], isNotNull);
      final rawToken = registerRes.data['token'] as String;
      expect(rawToken.isNotEmpty, isTrue);

      final user = UserModel.fromJson(registerRes.data['user']);
      expect(user.name, 'E2E Tester');
      expect(user.email, testEmail);

      // 2. Save token to TokenStorage
      await tokenStorage.saveToken(rawToken);
      expect(await tokenStorage.hasToken(), isTrue);

      // 3. Validate session via /auth/me
      final meRes = await apiClient.get<Map<String, dynamic>>('/auth/me');
      final fetchedUser = UserModel.fromJson(meRes.data);
      expect(fetchedUser.id, user.id);
      expect(fetchedUser.email, testEmail);

      // 4. Update profile via PATCH /profile
      final updateRes = await apiClient.patch<Map<String, dynamic>>(
        '/profile',
        data: {
          'name': 'E2E Tester Updated',
          'timezone': 'America/New_York',
        },
      );
      final updatedUser = UserModel.fromJson(updateRes.data);
      expect(updatedUser.name, 'E2E Tester Updated');
      expect(updatedUser.timezone, 'America/New_York');

      // 5. Create goal via POST /goals
      final goalRes = await apiClient.post<Map<String, dynamic>>(
        '/goals',
        data: {
          'category': 'fitness',
          'title': 'E2E Marathon Training',
          'target_description': 'Run 10km three times a week',
          'pace': 'steady',
        },
      );
      final createdGoal = GoalModel.fromJson(goalRes.data);
      expect(createdGoal.id.isNotEmpty, isTrue);
      expect(createdGoal.category, 'fitness');
      expect(createdGoal.title, 'E2E Marathon Training');
      expect(createdGoal.pace, 'steady');

      // 6. Query pods via GET /pods
      final podsRes = await apiClient.get<dynamic>('/pods');
      expect(podsRes.data, isA<List>());

      // 7. Login with newly created credentials
      await tokenStorage.deleteToken();
      expect(await tokenStorage.hasToken(), isFalse);

      final loginRes = await apiClient.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': testEmail,
          'password': testPassword,
        },
      );
      expect(loginRes.data['token'], isNotNull);
      final loginUser = UserModel.fromJson(loginRes.data['user']);
      expect(loginUser.id, user.id);
      expect(loginUser.email, testEmail);
    });
  });
}
