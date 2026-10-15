import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/router.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:mobile/features/auth/signup_screen.dart';
import 'package:mobile/features/auth/splash_screen.dart';
import 'package:mobile/features/matching/finding_match_screen.dart';
import 'package:mobile/features/matching/match_found_screen.dart';
import 'package:mobile/features/onboarding/goal_category_screen.dart';
import 'package:mobile/features/onboarding/goal_detail_screen.dart';
import 'package:mobile/features/onboarding/matching_prefs_screen.dart';
import 'package:mobile/features/onboarding/profile_setup_screen.dart';
import 'package:mobile/features/pods/pod_home_screen.dart';
import 'package:mobile/features/pods/pod_settings_screen.dart';
import 'package:mobile/features/todos/todo_detail_screen.dart';
import 'package:mobile/features/todos/todo_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Widget buildTestApp(GoRouter router, {TokenStorage? storage}) {
    return ProviderScope(
      overrides: [
        if (storage != null) tokenStorageProvider.overrideWithValue(storage),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
  }

  Future<void> pumpRouter(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Router Tests', () {
    test('Defines all 22 required route names', () {
      const expectedRoutes = [
        'splash',
        'login',
        'signup',
        'profile-setup',
        'goal-category',
        'goal-detail',
        'matching-prefs',
        'finding-match',
        'match-found',
        'pod-home',
        'pod-settings',
        'todo-list',
        'todo-detail',
        'chat',
        'checkin',
        'streak-detail',
        'streak-recovery',
        'profile',
        'notification-settings',
        'blocked-users',
        'report-form',
        'account-settings',
      ];

      expect(AppRoutes.allRouteNames.length, 22);
      for (final route in expectedRoutes) {
        expect(AppRoutes.allRouteNames.contains(route), isTrue,
            reason: 'Missing route: $route');
      }
    });

    testWidgets('App boots to splash screen by default',
        (WidgetTester tester) async {
      final storage = TokenStorage();
      final testRouter = createRouter(tokenStorage: storage);

      await tester.pumpWidget(buildTestApp(testRouter, storage: storage));
      await pumpRouter(tester);

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('Pair'), findsOneWidget);
    });

    testWidgets(
        'Public routes (/splash, /login, /signup) are accessible without token',
        (WidgetTester tester) async {
      final storage = TokenStorage();

      // Test /login
      final loginRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.loginPath,
      );
      await tester.pumpWidget(buildTestApp(loginRouter, storage: storage));
      await pumpRouter(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);

      // Test /signup
      final signupRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.signupPath,
      );
      await tester.pumpWidget(buildTestApp(signupRouter, storage: storage));
      await pumpRouter(tester);
      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('Protected routes redirect to /login when no token is stored',
        (WidgetTester tester) async {
      final storage = TokenStorage();

      final chatRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.chatPath,
      );

      await tester.pumpWidget(buildTestApp(chatRouter, storage: storage));
      await pumpRouter(tester);

      // Should have been redirected to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(AppRoutes.chat), findsNothing);
    });

    testWidgets('Protected routes are accessible when token is stored',
        (WidgetTester tester) async {
      final storage = TokenStorage();
      await storage.saveToken('valid-user-token');

      // Access /pod-home with valid token
      final podRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.podHomePath,
      );

      await tester.pumpWidget(buildTestApp(podRouter, storage: storage));
      await pumpRouter(tester);

      expect(find.byType(PodHomeScreen), findsOneWidget);

      // Navigate to /chat
      podRouter.go(AppRoutes.chatPath);
      await pumpRouter(tester);

      expect(find.text(AppRoutes.chat), findsAtLeastNWidgets(1));
    });

    testWidgets('First 13 routes render their respective feature screen widgets',
        (WidgetTester tester) async {
      final storage = TokenStorage();
      await storage.saveToken('authenticated-token');

      final testRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.loginPath,
      );

      await tester.pumpWidget(buildTestApp(testRouter, storage: storage));
      await pumpRouter(tester);

      // 1. Login
      expect(find.byType(LoginScreen), findsOneWidget);

      // 2. Signup
      testRouter.go(AppRoutes.signupPath);
      await pumpRouter(tester);
      expect(find.byType(SignupScreen), findsOneWidget);

      // 3. Profile Setup
      testRouter.go(AppRoutes.profileSetupPath);
      await pumpRouter(tester);
      expect(find.byType(ProfileSetupScreen), findsOneWidget);

      // 4. Goal Category
      testRouter.go(AppRoutes.goalCategoryPath);
      await pumpRouter(tester);
      expect(find.byType(GoalCategoryScreen), findsOneWidget);

      // 5. Goal Detail
      testRouter.go(AppRoutes.goalDetailPath);
      await pumpRouter(tester);
      expect(find.byType(GoalDetailScreen), findsOneWidget);

      // 6. Matching Prefs
      testRouter.go(AppRoutes.matchingPrefsPath);
      await pumpRouter(tester);
      expect(find.byType(MatchingPrefsScreen), findsOneWidget);

      // 7. Finding Match
      testRouter.go(AppRoutes.findingMatchPath);
      await pumpRouter(tester);
      expect(find.byType(FindingMatchScreen), findsOneWidget);

      // 8. Match Found
      testRouter.go(AppRoutes.matchFoundPath);
      await pumpRouter(tester);
      expect(find.byType(MatchFoundScreen), findsOneWidget);

      // 9. Pod Home
      testRouter.go(AppRoutes.podHomePath);
      await pumpRouter(tester);
      expect(find.byType(PodHomeScreen), findsOneWidget);

      // 10. Pod Settings
      testRouter.go(AppRoutes.podSettingsPath);
      await pumpRouter(tester);
      expect(find.byType(PodSettingsScreen), findsOneWidget);

      // 11. Todo List
      testRouter.go(AppRoutes.todoListPath);
      await pumpRouter(tester);
      expect(find.byType(TodoListScreen), findsOneWidget);

      // 12. Todo Detail
      testRouter.go(AppRoutes.todoDetailPath);
      await pumpRouter(tester);
      expect(find.byType(TodoDetailScreen), findsOneWidget);

      // Clean up widget tree
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Remaining routes render RouteStubScreen',
        (WidgetTester tester) async {
      final storage = TokenStorage();
      await storage.saveToken('authenticated-token');

      final remainingRoutes = [
        AppRoutes.chatPath,
        AppRoutes.checkinPath,
        AppRoutes.streakDetailPath,
        AppRoutes.streakRecoveryPath,
        AppRoutes.profilePath,
        AppRoutes.notificationSettingsPath,
        AppRoutes.blockedUsersPath,
        AppRoutes.reportFormPath,
        AppRoutes.accountSettingsPath,
      ];

      final testRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.chatPath,
      );

      await tester.pumpWidget(buildTestApp(testRouter, storage: storage));
      await tester.pump(const Duration(milliseconds: 100));

      for (final path in remainingRoutes) {
        testRouter.go(path);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(RouteStubScreen), findsAtLeastNWidgets(1));
      }
    });
  });
}
