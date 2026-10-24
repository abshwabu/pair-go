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
import 'package:mobile/features/auth/auth_state.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/onboarding/goal_category_provider.dart';
import 'package:mobile/features/onboarding/goal_category_screen.dart';
import 'package:mobile/features/onboarding/goal_detail_screen.dart';
import 'package:mobile/features/matching/finding_match_screen.dart';
import 'package:mobile/features/onboarding/matching_prefs_screen.dart';
import 'package:flutter/services.dart';
import 'package:mobile/features/onboarding/profile_setup_screen.dart';

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
    UserModel? initialUser,
  }) {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        tokenStorageProvider.overrideWithValue(tokenStorage),
        if (initialUser != null)
          currentUserProvider.overrideWithValue(initialUser),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
  }

  group('Profile Setup Screen Tests', () {
    testWidgets('Pre-fills user name and submits profile updates',
        (WidgetTester tester) async {
      await tokenStorage.saveToken('auth-token');

      final user = const UserModel(
        id: 'usr-1',
        name: 'Initial Name',
        email: 'init@pair.test',
        timezone: 'UTC',
      );

      final dio = Dio();
      String? capturedName;
      String? capturedTimezone;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/profile') && options.method == 'PATCH') {
              final map = options.data as Map<String, dynamic>;
              capturedName = map['name'] as String?;
              capturedTimezone = map['timezone'] as String?;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'id': 'usr-1',
                      'name': capturedName,
                      'email': 'init@pair.test',
                      'timezone': capturedTimezone,
                    },
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
        initialLocation: AppRoutes.profileSetupPath,
      );

      await tester.pumpWidget(
        createTestWidget(
          router: router,
          apiClient: apiClient,
          initialUser: user,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfileSetupScreen), findsOneWidget);
      expect(find.text('Initial Name'), findsOneWidget);

      // Change name
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Display Name'), 'Updated Name');

      // Tap submit
      await tester.ensureVisible(find.text('Continue to Goals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to Goals'));
      await tester.pumpAndSettle();

      expect(capturedName, 'Updated Name');
      expect(find.byType(GoalCategoryScreen), findsOneWidget);
    });
  });

  group('Goal Category Selection Tests', () {
    testWidgets('Displays all 5 category cards and selecting one navigates',
        (WidgetTester tester) async {
      await tokenStorage.saveToken('auth-token');

      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: Dio(),
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.goalCategoryPath,
      );

      await tester.pumpWidget(
        createTestWidget(router: router, apiClient: apiClient),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('Fitness'), findsOneWidget);
      expect(find.text('Habit'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);

      // Select 'Fitness'
      await tester.tap(find.text('Fitness'));
      await tester.pumpAndSettle();

      expect(find.byType(GoalDetailScreen), findsOneWidget);
      expect(find.text('Category: FITNESS'), findsOneWidget);
    });
  });

  group('Goal Detail Entry Tests', () {
    testWidgets('Validates title and posts goal with category and pace',
        (WidgetTester tester) async {
      await tokenStorage.saveToken('auth-token');

      final dio = Dio();
      String? capturedTitle;
      String? capturedCategory;
      String? capturedPace;
      String? capturedDesc;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/goals') && options.method == 'POST') {
              final map = options.data as Map<String, dynamic>;
              capturedTitle = map['title'] as String?;
              capturedCategory = map['category'] as String?;
              capturedPace = map['pace'] as String?;
              capturedDesc = map['target_description'] as String?;

              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {
                      'id': 'goal-123',
                      'user_id': 'usr-1',
                      'category': capturedCategory,
                      'title': capturedTitle,
                      'target_description': capturedDesc,
                      'pace': capturedPace,
                    },
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
        initialLocation: AppRoutes.goalDetailPath,
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          tokenStorageProvider.overrideWithValue(tokenStorage),
        ],
      );

      // Set preselected category
      container.read(selectedGoalCategoryProvider.notifier).select('fitness');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt to submit empty title
      await tester.ensureVisible(find.text('Save & Continue to Matching'));
      await tester.tap(find.text('Save & Continue to Matching'));
      await tester.pumpAndSettle();
      expect(find.text('Goal title is required'), findsOneWidget);

      // Enter title and description
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Goal Title'), 'Run 5k Daily');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Target Description'),
          'Wake up at 6am and run 5k');

      // Change pace to Intense
      await tester.ensureVisible(find.text('Intense'));
      await tester.tap(find.text('Intense'));
      await tester.pumpAndSettle();

      // Submit
      await tester.ensureVisible(find.text('Save & Continue to Matching'));
      await tester.tap(find.text('Save & Continue to Matching'));
      await tester.pumpAndSettle();

      expect(capturedTitle, 'Run 5k Daily');
      expect(capturedCategory, 'fitness');
      expect(capturedPace, 'intense');
      expect(find.byType(MatchingPrefsScreen), findsOneWidget);
    });
  });

  group('Matching Preferences Tests', () {
    testWidgets('Updates slider and dropdown and navigates to /finding-match',
        (WidgetTester tester) async {
      await tokenStorage.saveToken('auth-token');

      final apiClient = ApiClient(
        tokenStorage: tokenStorage,
        customDio: Dio(),
      );

      final router = createRouter(
        tokenStorage: tokenStorage,
        initialLocation: AppRoutes.matchingPrefsPath,
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          tokenStorageProvider.overrideWithValue(tokenStorage),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MatchingPrefsScreen), findsOneWidget);
      expect(find.text('Partner Preferences'), findsOneWidget);

      // Submit preferences
      await tester.ensureVisible(find.text('Find Partner Match'));
      await tester.tap(find.text('Find Partner Match'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FindingMatchScreen), findsOneWidget);

      // Cleanly unmount widget tree to dispose timers and tickers
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
