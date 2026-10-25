import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/router.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/widgets/error_banner.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/onboarding/profile_setup_screen.dart';
import 'package:mobile/features/pods/pod_home_screen.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenStorage tokenStorage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    tokenStorage = TokenStorage();

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

  Widget createTestWidget({
    required GoRouter router,
    required ApiClient apiClient,
    TokenStorage? storage,
  }) {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        tokenStorageProvider.overrideWithValue(storage ?? tokenStorage),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
  }

  group('Splash Screen Auth Checks', () {
    testWidgets('Routes to /login when no token is present',
        (WidgetTester tester) async {
      final dio = Dio();
      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.splashPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
        'Routes to /goal-category when token is valid and user has no active pods',
        (WidgetTester tester) async {
      await tokenStorage.saveToken('valid-token-123');

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/auth/me')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'id': 'u-1',
                      'name': 'Test User',
                      'email': 'test@example.com',
                      'timezone': 'UTC',
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path.contains('/matching/current')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'none',
                      'request_id': null,
                      'pod_id': null,
                      'proposal': null,
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path.contains('/pods')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [], // no active pods
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

      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.splashPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      expect(find.text('What is your main focus?'), findsOneWidget);
    });

    testWidgets(
        'Routes to /pod-home when token is valid and user has an active pod',
        (WidgetTester tester) async {
      await tokenStorage.saveToken('valid-token-123');

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/auth/me')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'id': 'u-1',
                      'name': 'Test User',
                      'email': 'test@example.com',
                      'timezone': 'UTC',
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path.contains('/matching/current')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'matched',
                      'request_id': null,
                      'pod_id': 'pod-1',
                      'proposal': null,
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path.contains('/pods')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {'id': 'pod-1', 'goal_category': 'read'}
                    ],
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

      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.splashPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PodHomeScreen), findsOneWidget);
    });

    testWidgets('Routes to /login and clears token when /auth/me fails',
        (WidgetTester tester) async {
      await tokenStorage.saveToken('expired-token');

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 401,
                  data: {
                    'data': null,
                    'meta': null,
                    'error': {
                      'message': 'Token expired',
                      'code': 'UNAUTHORIZED',
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.splashPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await tokenStorage.hasToken(), isFalse);
    });
  });

  group('Login Screen Tests', () {
    testWidgets('Shows client-side validation errors for empty fields',
        (WidgetTester tester) async {
      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: Dio(),
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.loginPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      // Tap submit with empty fields
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('Displays ErrorBanner when login API returns error',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 401,
                  data: {
                    'data': null,
                    'meta': null,
                    'error': {
                      'message': 'Invalid email or password',
                      'code': 'INVALID_CREDENTIALS',
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.loginPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      // Enter credentials
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'wrong@pair.test');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'wrongpass');
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('Invalid email or password'), findsAtLeastNWidgets(1));
    });
  });

  group('Signup Screen Tests', () {
    testWidgets('Validates passwords match and minimum length',
        (WidgetTester tester) async {
      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: Dio(),
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.signupPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      // Fill name and email but short password
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name'), 'Alice');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'alice@pair.test');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'short');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'), 'different');

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 8 characters long'),
          findsOneWidget);
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('Successful signup stores token and routes to /profile-setup',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 201,
                data: {
                  'data': {
                    'token': 'registered-token-789',
                    'user': {
                      'id': 'usr-789',
                      'name': 'Bob Ross',
                      'email': 'bob@pair.test',
                      'timezone': 'UTC',
                    },
                  },
                  'meta': null,
                  'error': null,
                },
              ),
            );
          },
        ),
      );

      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: dio,
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.signupPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name'), 'Bob Ross');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'bob@pair.test');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'secret123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'), 'secret123');

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileSetupScreen), findsOneWidget);
      expect(await tokenStorage.getToken(), 'registered-token-789');
    });
  });
}
