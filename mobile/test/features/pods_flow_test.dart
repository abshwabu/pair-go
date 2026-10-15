import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/router.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/auth_state.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/pods/models/pod_model.dart';
import 'package:mobile/features/pods/pod_home_screen.dart';
import 'package:mobile/features/pods/pod_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockPod = PodDetail(
    id: 'pod-abc',
    goalCategory: 'fitness',
    status: 'active',
    capacity: 2,
    members: const [
      PodMemberDetail(
        user: MemberPublicProfile(id: 'me', name: 'John Doe'),
        goal: MemberGoalInfo(
          id: 'g-1',
          title: 'My Morning Run',
          category: 'fitness',
          pace: 'steady',
        ),
      ),
      PodMemberDetail(
        user: MemberPublicProfile(id: 'partner-1', name: 'Alice Walker'),
        goal: MemberGoalInfo(
          id: 'g-2',
          title: 'Evening Cycling 20km',
          category: 'fitness',
          pace: 'intense',
        ),
      ),
    ],
    streak: const StreakSummary(currentStreak: 4, bestStreak: 7),
  );

  group('Pod Flow Widget Tests', () {
    testWidgets(
        'PodHomeScreen renders partner header, streak badge, open todos preview, and Chat FAB',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/pod-abc') {
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
            if (options.path == '/pods/pod-abc/todos') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'id': 't-1',
                        'pod_id': 'pod-abc',
                        'created_by': 'partner-1',
                        'title': 'Stretch for 15 minutes',
                        'is_done': false,
                        'due_date': '2026-10-15',
                      },
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

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      final router = GoRouter(
        initialLocation: AppRoutes.podHomePath,
        routes: [
          GoRoute(
            path: AppRoutes.podHomePath,
            builder: (context, state) => const PodHomeScreen(podId: 'pod-abc'),
          ),
          GoRoute(
            path: AppRoutes.chatPath,
            builder: (context, state) => const Scaffold(
              body: Text('Chat Screen Hub'),
            ),
          ),
          GoRoute(
            path: AppRoutes.todoListPath,
            builder: (context, state) => const Scaffold(
              body: Text('Todo List Screen Hub'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWith((ref) => const UserModel(
                  id: 'me',
                  email: 'john@example.com',
                  name: 'John Doe',
                  timezone: 'UTC',
                  language: 'en',
                )),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header partner info
      expect(find.text('Fitness Pod'), findsOneWidget);
      expect(find.text('Alice Walker'), findsOneWidget);
      expect(find.text('4 streak'), findsOneWidget);
      expect(find.text('Best: 7'), findsOneWidget);

      // Goals comparison
      expect(find.text('Evening Cycling 20km'), findsOneWidget);
      expect(find.text('My Morning Run'), findsOneWidget);

      // Daily Checkin
      expect(find.text('Daily Check-in'), findsOneWidget);

      // Open todos preview
      expect(find.text('Open Todos'), findsOneWidget);
      expect(find.text('Stretch for 15 minutes'), findsOneWidget);
      expect(find.text('Due: 2026-10-15'), findsOneWidget);

      // Chat FAB
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Chat Screen Hub'), findsOneWidget);
    });

    testWidgets(
        'PodSettingsScreen allows leave pod via confirmation dialog and routes to goal-category',
        (WidgetTester tester) async {
      bool leaveCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/pod-abc') {
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
            if (options.path == '/pods/pod-abc/leave' &&
                options.method == 'POST') {
              leaveCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'message': 'left pod successfully'},
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
        initialLocation: AppRoutes.podSettingsPath,
        routes: [
          GoRoute(
            path: AppRoutes.podSettingsPath,
            builder: (context, state) =>
                const PodSettingsScreen(podId: 'pod-abc'),
          ),
          GoRoute(
            path: AppRoutes.goalCategoryPath,
            builder: (context, state) => const Scaffold(
              body: Text('Goal Category Selection Screen'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWith((ref) => const UserModel(
                  id: 'me',
                  email: 'john@example.com',
                  name: 'John Doe',
                  timezone: 'UTC',
                  language: 'en',
                )),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Pod Settings'), findsOneWidget);
      expect(find.text('Leave Pod'), findsOneWidget);
      expect(find.text('Block Partner'), findsOneWidget);
      expect(find.text('Report Partner'), findsOneWidget);

      // Tap "Leave Pod"
      await tester.tap(find.text('Leave Pod'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Leave Pod?'), findsOneWidget);

      // Confirm leave
      await tester.tap(find.widgetWithText(FilledButton, 'Leave Pod'));
      await tester.pumpAndSettle();

      expect(leaveCalled, isTrue);
      expect(find.text('Goal Category Selection Screen'), findsOneWidget);
    });

    testWidgets(
        'PodSettingsScreen allows block partner via confirmation dialog and routes to goal-category',
        (WidgetTester tester) async {
      bool blockCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/pod-abc') {
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
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {
                      'id': 'b-1',
                      'user_id': 'me',
                      'blocked_user_id': 'partner-1',
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

      final router = GoRouter(
        initialLocation: AppRoutes.podSettingsPath,
        routes: [
          GoRoute(
            path: AppRoutes.podSettingsPath,
            builder: (context, state) =>
                const PodSettingsScreen(podId: 'pod-abc'),
          ),
          GoRoute(
            path: AppRoutes.goalCategoryPath,
            builder: (context, state) => const Scaffold(
              body: Text('Goal Category Selection Screen'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWith((ref) => const UserModel(
                  id: 'me',
                  email: 'john@example.com',
                  name: 'John Doe',
                  timezone: 'UTC',
                  language: 'en',
                )),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Block Partner"
      await tester.tap(find.text('Block Partner'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Block Partner?'), findsOneWidget);

      // Confirm block
      await tester.tap(find.widgetWithText(FilledButton, 'Block'));
      await tester.pumpAndSettle();

      expect(blockCalled, isTrue);
      expect(find.text('Goal Category Selection Screen'), findsOneWidget);
    });
  });
}
