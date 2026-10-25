import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/router.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/goals/models/goal_model.dart';
import 'package:mobile/features/matching/finding_match_screen.dart';
import 'package:mobile/features/matching/match_found_screen.dart';
import 'package:mobile/features/onboarding/goal_detail_provider.dart';
import 'package:mobile/features/pods/models/pod_model.dart';

class MockCreatedGoalNotifier extends CreatedGoalNotifier {
  final GoalModel? initialGoal;
  MockCreatedGoalNotifier(this.initialGoal);

  @override
  GoalModel? build() => initialGoal;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Matching Flow Widget Tests', () {
    testWidgets('FindingMatchScreen renders pulsing icon, rotating status, and cancel button',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/request' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {
                      'id': 'match-req-123',
                      'user_id': 'user-1',
                      'goal_id': 'goal-1',
                      'status': 'open',
                      'timezone_tolerance_hours': 3,
                      'language': 'en',
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

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      const testGoal = GoalModel(
        id: 'goal-1',
        userId: 'user-1',
        category: 'fitness',
        title: 'Run a 5k',
        targetDescription: 'Train 3x a week',
        pace: 'steady',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            createdGoalProvider.overrideWith(() => MockCreatedGoalNotifier(testGoal)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FindingMatchScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Finding your Pair'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      expect(find.text('Cancel Search'), findsOneWidget);
      expect(find.byIcon(Icons.people_alt_rounded), findsOneWidget);

      // Cleanly unmount to verify disposal of timers and animation controller
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('FindingMatchScreen cancel button triggers cancel and navigates',
        (WidgetTester tester) async {
      bool cancelCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/request' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {
                      'id': 'match-req-999',
                      'user_id': 'user-1',
                      'goal_id': 'goal-1',
                      'status': 'open',
                      'timezone_tolerance_hours': 3,
                      'language': 'en',
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/matching/request/match-req-999' &&
                options.method == 'DELETE') {
              cancelCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'message': 'cancelled'},
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

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      final router = GoRouter(
        initialLocation: AppRoutes.findingMatchPath,
        routes: [
          GoRoute(
            path: AppRoutes.findingMatchPath,
            builder: (context, state) => const FindingMatchScreen(),
          ),
          GoRoute(
            path: AppRoutes.matchingPrefsPath,
            builder: (context, state) => const Scaffold(
              body: Text('Matching Preferences Screen'),
            ),
          ),
        ],
      );

      const testGoal = GoalModel(
        id: 'goal-1',
        userId: 'user-1',
        category: 'fitness',
        title: 'Run a 5k',
        targetDescription: '',
        pace: 'steady',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            createdGoalProvider.overrideWith(() => MockCreatedGoalNotifier(testGoal)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap cancel search
      await tester.tap(find.text('Cancel Search'));
      await tester.pumpAndSettle();

      expect(cancelCalled, isTrue);
      expect(find.text('Matching Preferences Screen'), findsOneWidget);
    });

    testWidgets('MatchFoundScreen renders partner name, avatar, and goal celebratory card',
        (WidgetTester tester) async {
      final mockPod = PodDetail(
        id: 'pod-123',
        goalCategory: 'fitness',
        status: 'active',
        capacity: 2,
        members: const [
          PodMemberDetail(
            user: MemberPublicProfile(id: 'me', name: 'John Doe'),
            goal: MemberGoalInfo(
              id: 'g-1',
              title: 'My 5k goal',
              category: 'fitness',
              pace: 'steady',
            ),
          ),
          PodMemberDetail(
            user: MemberPublicProfile(
              id: 'partner-1',
              name: 'Sarah Smith',
              avatarUrl: null,
            ),
            goal: MemberGoalInfo(
              id: 'g-2',
              title: 'Run 10km every weekend',
              category: 'fitness',
              pace: 'intense',
            ),
          ),
        ],
        streak: const StreakSummary(currentStreak: 0, bestStreak: 0),
      );

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/pod-123') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': mockPod.toJson(),
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

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      final router = GoRouter(
        initialLocation: AppRoutes.matchFoundPath,
        routes: [
          GoRoute(
            path: AppRoutes.matchFoundPath,
            builder: (context, state) =>
                const MatchFoundScreen(podId: 'pod-123'),
          ),
          GoRoute(
            path: AppRoutes.podHomePath,
            builder: (context, state) => const Scaffold(
              body: Text('Pod Home Screen Hub'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("It's a Match!"), findsOneWidget);
      expect(find.text('Sarah Smith'), findsOneWidget);
      expect(find.text('Run 10km every weekend'), findsOneWidget);
      expect(find.text('FITNESS'), findsOneWidget);
      expect(find.text('intense pace'), findsOneWidget);

      // Tap "Let's start"
      await tester.ensureVisible(find.text("Let's start"));
      await tester.tap(find.text("Let's start"));
      await tester.pumpAndSettle();

      expect(find.text('Pod Home Screen Hub'), findsOneWidget);
    });

    testWidgets('MatchFoundScreen Reject Suggestion leaves pod and navigates back',
        (WidgetTester tester) async {
      final mockPod = PodDetail(
        id: 'pod-reject-1',
        goalCategory: 'fitness',
        status: 'active',
        capacity: 2,
        members: const [
          PodMemberDetail(
            user: MemberPublicProfile(id: 'me', name: 'John Doe'),
            goal: MemberGoalInfo(
              id: 'g-1',
              title: 'My 5k goal',
              category: 'fitness',
              pace: 'steady',
            ),
          ),
          PodMemberDetail(
            user: MemberPublicProfile(
              id: 'partner-99',
              name: 'Candidate Alex',
            ),
            goal: MemberGoalInfo(
              id: 'g-2',
              title: 'Run every morning',
              category: 'fitness',
              pace: 'steady',
            ),
          ),
        ],
        streak: const StreakSummary(currentStreak: 0, bestStreak: 0),
      );

      bool leaveCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/pod-reject-1' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': mockPod.toJson(),
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/pods/pod-reject-1/leave' && options.method == 'POST') {
              leaveCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'status': 'left'},
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

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      final router = GoRouter(
        initialLocation: AppRoutes.matchFoundPath,
        routes: [
          GoRoute(
            path: AppRoutes.matchFoundPath,
            builder: (context, state) =>
                const MatchFoundScreen(podId: 'pod-reject-1'),
          ),
          GoRoute(
            path: AppRoutes.matchingPrefsPath,
            builder: (context, state) => const Scaffold(
              body: Text('Matching Preferences Screen'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reject Suggestion'), findsOneWidget);

      await tester.ensureVisible(find.text('Reject Suggestion'));
      await tester.tap(find.text('Reject Suggestion'));
      await tester.pumpAndSettle();

      // Confirmation dialog should be visible
      expect(find.text('Reject Suggestion?'), findsOneWidget);
      expect(find.text("Don't suggest this user again (block)"), findsOneWidget);

      // Tap confirm Reject Suggestion in dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Reject Suggestion'));
      await tester.pumpAndSettle();

      expect(leaveCalled, isTrue);
      expect(find.text('Matching Preferences Screen'), findsOneWidget);
    });

    testWidgets('MatchFoundScreen Reject Suggestion with block calls block API',
        (WidgetTester tester) async {
      final mockPod = PodDetail(
        id: 'pod-reject-2',
        goalCategory: 'fitness',
        status: 'active',
        capacity: 2,
        members: const [
          PodMemberDetail(
            user: MemberPublicProfile(id: 'me', name: 'John Doe'),
            goal: MemberGoalInfo(
              id: 'g-1',
              title: 'My 5k goal',
              category: 'fitness',
              pace: 'steady',
            ),
          ),
          PodMemberDetail(
            user: MemberPublicProfile(
              id: 'partner-block-me',
              name: 'Candidate Sam',
            ),
            goal: MemberGoalInfo(
              id: 'g-2',
              title: 'Daily cycling',
              category: 'fitness',
              pace: 'steady',
            ),
          ),
        ],
        streak: const StreakSummary(currentStreak: 0, bestStreak: 0),
      );

      bool blockCalled = false;
      String? blockedUserId;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/pod-reject-2' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': mockPod.toJson(),
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/blocks' && options.method == 'POST') {
              blockCalled = true;
              blockedUserId = (options.data as Map)['blocked_user_id'];
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {'id': 'b-1', 'blocked_user_id': blockedUserId},
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

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      final router = GoRouter(
        initialLocation: AppRoutes.matchFoundPath,
        routes: [
          GoRoute(
            path: AppRoutes.matchFoundPath,
            builder: (context, state) =>
                const MatchFoundScreen(podId: 'pod-reject-2'),
          ),
          GoRoute(
            path: AppRoutes.matchingPrefsPath,
            builder: (context, state) => const Scaffold(
              body: Text('Matching Preferences Screen'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Reject Suggestion'));
      await tester.tap(find.text('Reject Suggestion'));
      await tester.pumpAndSettle();

      // Check the block checkbox
      await tester.tap(find.text("Don't suggest this user again (block)"));
      await tester.pumpAndSettle();

      // Tap confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Reject Suggestion'));
      await tester.pumpAndSettle();

      expect(blockCalled, isTrue);
      expect(blockedUserId, equals('partner-block-me'));
      expect(find.text('Matching Preferences Screen'), findsOneWidget);
    });
  });
}
