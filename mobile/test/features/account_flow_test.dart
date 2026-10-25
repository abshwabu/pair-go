import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/account/account_settings_screen.dart';
import 'package:mobile/features/account/blocked_users_screen.dart';
import 'package:mobile/features/account/notification_settings_screen.dart';
import 'package:mobile/features/account/profile_screen.dart';
import 'package:mobile/features/account/report_form_screen.dart';
import 'package:mobile/features/auth/auth_state.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/onboarding/profile_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthNotifier extends AuthNotifier {
  final UserModel? _initialUser;
  MockAuthNotifier(this._initialUser);

  @override
  AuthState build() {
    return AuthState(
      isAuthenticated: _initialUser != null,
      user: _initialUser,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getLocalTimezone') {
          return 'UTC';
        }
        return null;
      },
    );
  });

  const mockUser = UserModel(
    id: 'user-123',
    email: 'alex@example.com',
    name: 'Alex Rivera',
    avatarUrl: null,
    timezone: 'America/New_York',
    language: 'en',
  );

  Widget createTestWidget({
    required GoRouter router,
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
    UserModel? initialUser,
  }) {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        tokenStorageProvider.overrideWithValue(tokenStorage),
        authNotifierProvider.overrideWith(() => MockAuthNotifier(initialUser)),
        currentUserProvider.overrideWith((ref) => initialUser),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.darkTheme,
      ),
    );
  }

  group('Profile Screen Tests', () {
    testWidgets('Displays profile info and navigates to edit profile',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/profile' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': mockUser.toJson(),
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final tokenStorage = TokenStorage();
      await tokenStorage.saveToken('test-token');
      final apiClient = ApiClient(tokenStorage: tokenStorage, customDio: dio);

      final testRouter = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/profile-setup',
            builder: (context, state) => const ProfileSetupScreen(isEditing: true),
          ),
          GoRoute(
            path: '/notification-settings',
            builder: (context, state) => const NotificationSettingsScreen(),
          ),
          GoRoute(
            path: '/blocked-users',
            builder: (context, state) => const BlockedUsersScreen(),
          ),
          GoRoute(
            path: '/account-settings',
            builder: (context, state) => const AccountSettingsScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(
          router: testRouter,
          apiClient: apiClient,
          tokenStorage: tokenStorage,
          initialUser: mockUser,
        ),
      );
      await tester.pumpAndSettle();

      // Verify profile screen details
      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('alex@example.com'), findsOneWidget);
      expect(find.text('America/New_York'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      // Verify action items exist
      expect(find.text('Notification Settings'), findsOneWidget);
      expect(find.text('Blocked Users'), findsOneWidget);
      expect(find.text('Account Settings'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);

      // Tap Edit Profile button
      final editButton = find.text('Edit Profile');
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Should navigate to ProfileSetupScreen with edit mode (title: Edit Profile)
      expect(find.text('Edit Profile'), findsAtLeastNWidgets(1));
      expect(find.text('Save Changes'), findsOneWidget);
    });
  });

  group('Notification Settings Tests', () {
    testWidgets('Toggles notification preferences and renders notifications list',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'pref_notification_new_message': true,
        'pref_notification_checkin_nudge': true,
        'pref_notification_streak_broken': false,
        'pref_notification_match_found': true,
      });

      var markReadCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/notifications' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'id': 'notif-1',
                        'user_id': 'user-123',
                        'type': 'new_message',
                        'title': 'New Message',
                        'body': 'Alice sent a message',
                        'payload': '{"title":"New Message","body":"Alice sent a message","pod_id":"pod-999"}',
                        'read_at': null,
                        'created_at': DateTime.now().toIso8601String(),
                      },
                    ],
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/notifications/notif-1/read' && options.method == 'PATCH') {
              markReadCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'id': 'notif-1', 'status': 'read'},
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final tokenStorage = TokenStorage();
      await tokenStorage.saveToken('test-token');
      final apiClient = ApiClient(tokenStorage: tokenStorage, customDio: dio);

      final testRouter = GoRouter(
        initialLocation: '/notification-settings',
        routes: [
          GoRoute(
            path: '/notification-settings',
            builder: (context, state) => const NotificationSettingsScreen(),
          ),
          GoRoute(
            path: '/chat',
            builder: (context, state) => const Scaffold(body: Text('Chat Destination')),
          ),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(
          router: testRouter,
          apiClient: apiClient,
          tokenStorage: tokenStorage,
          initialUser: mockUser,
        ),
      );
      await tester.pumpAndSettle();

      // Verify toggles
      expect(find.text('Chat Messages'), findsOneWidget);
      expect(find.text('Check-in Nudges'), findsOneWidget);
      expect(find.text('Streak Alerts'), findsOneWidget);
      expect(find.text('Match Proposals'), findsOneWidget);
      expect(find.text('Match Confirmed'), findsOneWidget);
      expect(find.text('Match Updates'), findsOneWidget);

      // Verify in-app notifications section
      expect(find.text('New Message'), findsOneWidget);
      expect(find.text('Alice sent a message'), findsOneWidget);

      // Tap notification item to mark read and route
      await tester.tap(find.text('New Message'));
      await tester.pumpAndSettle();

      expect(markReadCalled, isTrue);
      expect(find.text('Chat Destination'), findsOneWidget);
    });
  });

  group('Blocked Users Screen Tests', () {
    testWidgets('Lists blocked users and unblocks a user on confirmation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var unblockCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/blocks' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'id': 'block-1',
                        'user_id': 'user-123',
                        'blocked_user_id': 'bad-user-456',
                        'name': 'Bad Actor',
                        'avatar_url': null,
                        'created_at': DateTime.now().toIso8601String(),
                      },
                    ],
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/blocks/block-1' && options.method == 'DELETE') {
              unblockCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'success': true},
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final tokenStorage = TokenStorage();
      await tokenStorage.saveToken('test-token');
      final apiClient = ApiClient(tokenStorage: tokenStorage, customDio: dio);

      final testRouter = GoRouter(
        initialLocation: '/blocked-users',
        routes: [
          GoRoute(
            path: '/blocked-users',
            builder: (context, state) => const BlockedUsersScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(
          router: testRouter,
          apiClient: apiClient,
          tokenStorage: tokenStorage,
          initialUser: mockUser,
        ),
      );
      await tester.pumpAndSettle();

      // Check blocked user is visible
      expect(find.text('Bad Actor'), findsOneWidget);

      // Tap unblock button
      final unblockButton = find.text('Unblock');
      expect(unblockButton, findsOneWidget);
      await tester.tap(unblockButton);
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Unblock Bad Actor?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await tester.pumpAndSettle();

      expect(unblockCalled, isTrue);
      // User should no longer be displayed
      expect(find.text('Bad Actor'), findsNothing);
      expect(find.text('No Blocked Users'), findsOneWidget);
    });
  });

  group('Report Form Tests', () {
    testWidgets('Validates 10-1000 character length and submits report',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Map<String, dynamic>? submittedBody;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/reports' && options.method == 'POST') {
              submittedBody = options.data as Map<String, dynamic>;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {'id': 'report-789', 'status': 'open'},
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final tokenStorage = TokenStorage();
      await tokenStorage.saveToken('test-token');
      final apiClient = ApiClient(tokenStorage: tokenStorage, customDio: dio);

      final testRouter = GoRouter(
        initialLocation: '/report-form',
        routes: [
          GoRoute(
            path: '/report-form',
            builder: (context, state) => const ReportFormScreen(
              reportedUserId: 'partner-99',
              podId: 'pod-88',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(
          router: testRouter,
          apiClient: apiClient,
          tokenStorage: tokenStorage,
          initialUser: mockUser,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Submit Report'), findsAtLeastNWidgets(1));

      // Try typing less than 10 characters
      await tester.enterText(find.byType(TextFormField), 'Too short');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Report'));
      await tester.pumpAndSettle();

      expect(find.text('Reason must be at least 10 characters long'), findsOneWidget);
      expect(submittedBody, isNull);

      // Enter valid report reason
      final validReason = 'This user engaged in repeated abusive language and harassment.';
      await tester.enterText(find.byType(TextFormField), validReason);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Report'));
      await tester.pumpAndSettle();

      expect(submittedBody, isNotNull);
      expect(submittedBody!['reported_user_id'], 'partner-99');
      expect(submittedBody!['pod_id'], 'pod-88');
      expect(submittedBody!['reason'], validReason);
    });
  });

  group('Account Settings Tests', () {
    testWidgets('Changes password and triggers delete account flow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Map<String, dynamic>? passwordChangeBody;
      var deleteAccountCalled = false;

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/profile/password' && options.method == 'PATCH') {
              passwordChangeBody = options.data as Map<String, dynamic>;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'success': true},
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/profile' && options.method == 'DELETE') {
              deleteAccountCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'success': true},
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final tokenStorage = TokenStorage();
      await tokenStorage.saveToken('test-token');
      final apiClient = ApiClient(tokenStorage: tokenStorage, customDio: dio);

      final testRouter = GoRouter(
        initialLocation: '/account-settings',
        routes: [
          GoRoute(
            path: '/account-settings',
            builder: (context, state) => const AccountSettingsScreen(),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(
          router: testRouter,
          apiClient: apiClient,
          tokenStorage: tokenStorage,
          initialUser: mockUser,
        ),
      );
      await tester.pumpAndSettle();

      // Test password change validation & submission
      expect(find.text('Account Settings'), findsOneWidget);
      expect(find.text('Change Password'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current Password'),
        'OldPassword123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Password'),
        'NewPassword123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm New Password'),
        'NewPassword123!',
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Update Password'));
      await tester.pumpAndSettle();

      expect(passwordChangeBody, isNotNull);
      expect(passwordChangeBody!['current_password'], 'OldPassword123!');
      expect(passwordChangeBody!['new_password'], 'NewPassword123!');

      // Test Delete Account flow
      expect(find.text('DANGER ZONE'), findsOneWidget);
      final deleteBtn = find.widgetWithText(FilledButton, 'Delete Account');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Delete Account?'), findsOneWidget);
      final confirmDeleteBtn = find.widgetWithText(FilledButton, 'Permanently Delete');
      expect(confirmDeleteBtn, findsOneWidget);
      await tester.tap(confirmDeleteBtn);
      await tester.pumpAndSettle();

      expect(deleteAccountCalled, isTrue);
      // Verify token cleared and user routed to /login
      expect(await tokenStorage.getToken(), isNull);
      expect(find.text('Login Screen'), findsOneWidget);
    });
  });
}
