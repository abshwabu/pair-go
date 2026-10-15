import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'storage/token_storage.dart';
import 'theme/app_theme.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/matching/finding_match_screen.dart';
import '../features/matching/match_found_screen.dart';
import '../features/onboarding/goal_category_screen.dart';
import '../features/onboarding/goal_detail_screen.dart';
import '../features/onboarding/matching_prefs_screen.dart';
import '../features/onboarding/profile_setup_screen.dart';
import '../features/pods/pod_home_screen.dart';
import '../features/pods/pod_settings_screen.dart';

/// String constants for all route names and paths.
class AppRoutes {
  AppRoutes._();

  static const String splash = 'splash';
  static const String login = 'login';
  static const String signup = 'signup';
  static const String profileSetup = 'profile-setup';
  static const String goalCategory = 'goal-category';
  static const String goalDetail = 'goal-detail';
  static const String matchingPrefs = 'matching-prefs';
  static const String findingMatch = 'finding-match';
  static const String matchFound = 'match-found';
  static const String podHome = 'pod-home';
  static const String podSettings = 'pod-settings';
  static const String todoList = 'todo-list';
  static const String todoDetail = 'todo-detail';
  static const String chat = 'chat';
  static const String checkin = 'checkin';
  static const String streakDetail = 'streak-detail';
  static const String streakRecovery = 'streak-recovery';
  static const String profile = 'profile';
  static const String notificationSettings = 'notification-settings';
  static const String blockedUsers = 'blocked-users';
  static const String reportForm = 'report-form';
  static const String accountSettings = 'account-settings';

  static const String splashPath = '/splash';
  static const String loginPath = '/login';
  static const String signupPath = '/signup';
  static const String profileSetupPath = '/profile-setup';
  static const String goalCategoryPath = '/goal-category';
  static const String goalDetailPath = '/goal-detail';
  static const String matchingPrefsPath = '/matching-prefs';
  static const String findingMatchPath = '/finding-match';
  static const String matchFoundPath = '/match-found';
  static const String podHomePath = '/pod-home';
  static const String podSettingsPath = '/pod-settings';
  static const String todoListPath = '/todo-list';
  static const String todoDetailPath = '/todo-detail';
  static const String chatPath = '/chat';
  static const String checkinPath = '/checkin';
  static const String streakDetailPath = '/streak-detail';
  static const String streakRecoveryPath = '/streak-recovery';
  static const String profilePath = '/profile';
  static const String notificationSettingsPath = '/notification-settings';
  static const String blockedUsersPath = '/blocked-users';
  static const String reportFormPath = '/report-form';
  static const String accountSettingsPath = '/account-settings';

  static const List<String> allRouteNames = [
    splash,
    login,
    signup,
    profileSetup,
    goalCategory,
    goalDetail,
    matchingPrefs,
    findingMatch,
    matchFound,
    podHome,
    podSettings,
    todoList,
    todoDetail,
    chat,
    checkin,
    streakDetail,
    streakRecovery,
    profile,
    notificationSettings,
    blockedUsers,
    reportForm,
    accountSettings,
  ];
}

/// Generic route stub widget that displays the route name as text.
/// Uses AppTheme and Theme.of(context) styling with zero hardcoded colors.
class RouteStubScreen extends StatelessWidget {
  final String routeName;

  const RouteStubScreen({
    super.key,
    required this.routeName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(routeName),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                routeName,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Route stub: $routeName',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Creates a [GoRouter] configured with all 22 route stubs, initial splash screen,
/// and auth redirect guard checking [TokenStorage].
GoRouter createRouter({
  TokenStorage? tokenStorage,
  String initialLocation = AppRoutes.splashPath,
}) {
  final storage = tokenStorage ?? TokenStorage();

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: storage,
    redirect: (BuildContext context, GoRouterState state) async {
      final location = state.uri.path;

      // Root path redirects to splash
      if (location == '/') {
        return AppRoutes.splashPath;
      }

      final hasToken = await storage.hasToken();
      final isPublic = location == AppRoutes.splashPath ||
          location == AppRoutes.loginPath ||
          location == AppRoutes.signupPath;

      // If no token is stored, all routes except /splash, /login, and /signup redirect to /login
      if (!hasToken && !isPublic) {
        return AppRoutes.loginPath;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => AppRoutes.splashPath,
      ),
      GoRoute(
        name: AppRoutes.splash,
        path: AppRoutes.splashPath,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        name: AppRoutes.login,
        path: AppRoutes.loginPath,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        name: AppRoutes.signup,
        path: AppRoutes.signupPath,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        name: AppRoutes.profileSetup,
        path: AppRoutes.profileSetupPath,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        name: AppRoutes.goalCategory,
        path: AppRoutes.goalCategoryPath,
        builder: (context, state) => const GoalCategoryScreen(),
      ),
      GoRoute(
        name: AppRoutes.goalDetail,
        path: AppRoutes.goalDetailPath,
        builder: (context, state) => const GoalDetailScreen(),
      ),
      GoRoute(
        name: AppRoutes.matchingPrefs,
        path: AppRoutes.matchingPrefsPath,
        builder: (context, state) => const MatchingPrefsScreen(),
      ),
      GoRoute(
        name: AppRoutes.findingMatch,
        path: AppRoutes.findingMatchPath,
        builder: (context, state) => const FindingMatchScreen(),
      ),
      GoRoute(
        name: AppRoutes.matchFound,
        path: AppRoutes.matchFoundPath,
        builder: (context, state) {
          final podId = state.extra as String? ??
              state.uri.queryParameters['pod_id'] ??
              state.uri.queryParameters['id'];
          return MatchFoundScreen(podId: podId);
        },
      ),
      GoRoute(
        name: AppRoutes.podHome,
        path: AppRoutes.podHomePath,
        builder: (context, state) {
          final podId = state.extra as String? ??
              state.uri.queryParameters['pod_id'] ??
              state.uri.queryParameters['id'];
          return PodHomeScreen(podId: podId);
        },
      ),
      GoRoute(
        name: AppRoutes.podSettings,
        path: AppRoutes.podSettingsPath,
        builder: (context, state) {
          final podId = state.extra as String? ??
              state.uri.queryParameters['pod_id'] ??
              state.uri.queryParameters['id'];
          return PodSettingsScreen(podId: podId);
        },
      ),
      GoRoute(
        name: AppRoutes.todoList,
        path: AppRoutes.todoListPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.todoList),
      ),
      GoRoute(
        name: AppRoutes.todoDetail,
        path: AppRoutes.todoDetailPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.todoDetail),
      ),
      GoRoute(
        name: AppRoutes.chat,
        path: AppRoutes.chatPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.chat),
      ),
      GoRoute(
        name: AppRoutes.checkin,
        path: AppRoutes.checkinPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.checkin),
      ),
      GoRoute(
        name: AppRoutes.streakDetail,
        path: AppRoutes.streakDetailPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.streakDetail),
      ),
      GoRoute(
        name: AppRoutes.streakRecovery,
        path: AppRoutes.streakRecoveryPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.streakRecovery),
      ),
      GoRoute(
        name: AppRoutes.profile,
        path: AppRoutes.profilePath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.profile),
      ),
      GoRoute(
        name: AppRoutes.notificationSettings,
        path: AppRoutes.notificationSettingsPath,
        builder: (context, state) =>
            const RouteStubScreen(routeName: AppRoutes.notificationSettings),
      ),
      GoRoute(
        name: AppRoutes.blockedUsers,
        path: AppRoutes.blockedUsersPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.blockedUsers),
      ),
      GoRoute(
        name: AppRoutes.reportForm,
        path: AppRoutes.reportFormPath,
        builder: (context, state) => const RouteStubScreen(routeName: AppRoutes.reportForm),
      ),
      GoRoute(
        name: AppRoutes.accountSettings,
        path: AppRoutes.accountSettingsPath,
        builder: (context, state) =>
            const RouteStubScreen(routeName: AppRoutes.accountSettings),
      ),
    ],
  );
}

/// Standalone router instance with default storage.
final router = createRouter();

/// Riverpod provider exposing [GoRouter] wired with the scoped [TokenStorage].
final routerProvider = Provider<GoRouter>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return createRouter(tokenStorage: tokenStorage);
});
