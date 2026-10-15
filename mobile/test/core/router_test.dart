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
import 'package:mobile/features/onboarding/goal_category_screen.dart';
import 'package:mobile/features/onboarding/goal_detail_screen.dart';
import 'package:mobile/features/onboarding/matching_prefs_screen.dart';
import 'package:mobile/features/onboarding/profile_setup_screen.dart';

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
      await tester.pump();

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
      await tester.pump();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);

      // Test /signup
      final signupRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.signupPath,
      );
      await tester.pumpWidget(buildTestApp(signupRouter, storage: storage));
      await tester.pump();
      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('Protected routes redirect to /login when no token is stored',
        (WidgetTester tester) async {
      final storage = TokenStorage();

      // Try accessing protected route /pod-home without token
      final podRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.podHomePath,
      );

      await tester.pumpWidget(buildTestApp(podRouter, storage: storage));
      await tester.pump();

      // Should have been redirected to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text(AppRoutes.podHome), findsNothing);

      // Try accessing protected route /chat without token
      final chatRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.chatPath,
      );

      await tester.pumpWidget(buildTestApp(chatRouter, storage: storage));
      await tester.pump();

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
      await tester.pumpAndSettle();

      expect(find.text(AppRoutes.podHome), findsAtLeastNWidgets(1));

      // Navigate to /chat
      podRouter.go(AppRoutes.chatPath);
      await tester.pumpAndSettle();

      expect(find.text(AppRoutes.chat), findsAtLeastNWidgets(1));
    });

    testWidgets('First 7 routes render their respective feature screen widgets',
        (WidgetTester tester) async {
      final storage = TokenStorage();
      await storage.saveToken('authenticated-token');

      final testRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.loginPath,
      );

      await tester.pumpWidget(buildTestApp(testRouter, storage: storage));
      await tester.pumpAndSettle();

      // Login
      expect(find.byType(LoginScreen), findsOneWidget);

      // Signup
      testRouter.go(AppRoutes.signupPath);
      await tester.pumpAndSettle();
      expect(find.byType(SignupScreen), findsOneWidget);

      // Profile Setup
      testRouter.go(AppRoutes.profileSetupPath);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSetupScreen), findsOneWidget);

      // Goal Category
      testRouter.go(AppRoutes.goalCategoryPath);
      await tester.pumpAndSettle();
      expect(find.byType(GoalCategoryScreen), findsOneWidget);

      // Goal Detail
      testRouter.go(AppRoutes.goalDetailPath);
      await tester.pumpAndSettle();
      expect(find.byType(GoalDetailScreen), findsOneWidget);

      // Matching Prefs
      testRouter.go(AppRoutes.matchingPrefsPath);
      await tester.pumpAndSettle();
      expect(find.byType(MatchingPrefsScreen), findsOneWidget);
    });

    testWidgets('Remaining routes render RouteStubScreen',
        (WidgetTester tester) async {
      final storage = TokenStorage();
      await storage.saveToken('authenticated-token');

      final remainingRoutes = [
        AppRoutes.findingMatchPath,
        AppRoutes.matchFoundPath,
        AppRoutes.podHomePath,
        AppRoutes.podSettingsPath,
        AppRoutes.todoListPath,
        AppRoutes.todoDetailPath,
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
        initialLocation: AppRoutes.findingMatchPath,
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
