import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

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

    testWidgets('App boots to splash screen by default', (WidgetTester tester) async {
      final storage = TokenStorage();
      final testRouter = createRouter(tokenStorage: storage);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: testRouter,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RouteStubScreen), findsOneWidget);
      expect(find.text(AppRoutes.splash), findsAtLeastNWidgets(1));
    });

    testWidgets('Public routes (/splash, /login, /signup) are accessible without token',
        (WidgetTester tester) async {
      final storage = TokenStorage();

      // Test /login
      final loginRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.loginPath,
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: loginRouter,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppRoutes.login), findsAtLeastNWidgets(1));

      // Test /signup
      final signupRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.signupPath,
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: signupRouter,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppRoutes.signup), findsAtLeastNWidgets(1));
    });

    testWidgets('Protected routes redirect to /login when no token is stored',
        (WidgetTester tester) async {
      final storage = TokenStorage();

      // Try accessing protected route /pod-home without token
      final podRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.podHomePath,
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: podRouter,
        ),
      );
      await tester.pumpAndSettle();

      // Should have been redirected to /login
      expect(find.text(AppRoutes.login), findsAtLeastNWidgets(1));
      expect(find.text(AppRoutes.podHome), findsNothing);

      // Try accessing protected route /chat without token
      final chatRouter = createRouter(
        tokenStorage: storage,
        initialLocation: AppRoutes.chatPath,
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: chatRouter,
        ),
      );
      await tester.pumpAndSettle();

      // Should have been redirected to /login
      expect(find.text(AppRoutes.login), findsAtLeastNWidgets(1));
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

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: podRouter,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppRoutes.podHome), findsAtLeastNWidgets(1));

      // Navigate to /chat
      podRouter.go(AppRoutes.chatPath);
      await tester.pumpAndSettle();

      expect(find.text(AppRoutes.chat), findsAtLeastNWidgets(1));
    });

    testWidgets('All 22 route stubs render their respective route names',
        (WidgetTester tester) async {
      final storage = TokenStorage();
      await storage.saveToken('authenticated-token');

      final routes = [
        AppRoutes.splashPath,
        AppRoutes.loginPath,
        AppRoutes.signupPath,
        AppRoutes.profileSetupPath,
        AppRoutes.goalCategoryPath,
        AppRoutes.goalDetailPath,
        AppRoutes.matchingPrefsPath,
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
        initialLocation: AppRoutes.splashPath,
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: testRouter,
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < routes.length; i++) {
        final path = routes[i];
        final expectedName = AppRoutes.allRouteNames[i];

        testRouter.go(path);
        await tester.pumpAndSettle();

        expect(find.text(expectedName), findsAtLeastNWidgets(1),
            reason: 'Failed to display route name for $path');
      }
    });
  });
}
