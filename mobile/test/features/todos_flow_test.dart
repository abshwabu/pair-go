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
import 'package:mobile/features/pods/pod_state.dart';
import 'package:mobile/features/todos/models/todo_model.dart';
import 'package:mobile/features/todos/todo_detail_screen.dart';
import 'package:mobile/features/todos/todo_list_screen.dart';
import 'package:mobile/features/todos/widgets/add_edit_todo_modal.dart';

class MockCurrentPodIdNotifier extends CurrentPodIdNotifier {
  final String? initialId;
  MockCurrentPodIdNotifier(this.initialId);
  @override
  String? build() => initialId;
}

class MockActivePodDetailNotifier extends ActivePodDetailNotifier {
  final PodDetail? initialPod;
  MockActivePodDetailNotifier(this.initialPod);
  @override
  ActivePodDetailState build() => ActivePodDetailState(pod: initialPod);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentUserId = 'user-me';
  const partnerId = 'user-partner';
  const podId = 'pod-123';

  final currentUser = const UserModel(
    id: currentUserId,
    email: 'me@pair.test',
    name: 'Me Myself',
    timezone: 'UTC',
    language: 'en',
  );

  final mockPod = PodDetail(
    id: podId,
    goalCategory: 'learning',
    status: 'active',
    capacity: 2,
    members: const [
      PodMemberDetail(
        user: MemberPublicProfile(id: currentUserId, name: 'Me Myself'),
        goal: MemberGoalInfo(
          id: 'g-1',
          title: 'Learn Go and Flutter',
          category: 'learning',
          pace: 'steady',
        ),
      ),
      PodMemberDetail(
        user: MemberPublicProfile(id: partnerId, name: 'Alice Walker'),
        goal: MemberGoalInfo(
          id: 'g-2',
          title: 'Master Go Concurrency',
          category: 'learning',
          pace: 'intense',
        ),
      ),
    ],
    streak: const StreakSummary(currentStreak: 5, bestStreak: 10),
  );

  final sampleTodos = [
    TodoModel(
      id: 'todo-mine',
      podId: podId,
      createdBy: currentUserId,
      assignedTo: currentUserId,
      title: 'Finish Flutter widget tests',
      notes: 'Ensure 100% pass',
      dueDate: '2026-10-25',
      isDone: false,
    ),
    TodoModel(
      id: 'todo-partner',
      podId: podId,
      createdBy: partnerId,
      assignedTo: partnerId,
      title: 'Review Go API endpoints',
      notes: 'Check SQL transactions',
      dueDate: '2026-10-26',
      isDone: false,
    ),
    TodoModel(
      id: 'todo-shared',
      podId: podId,
      createdBy: currentUserId,
      assignedTo: null, // Shared
      title: 'Weekly check-in sync',
      notes: 'Review streaks together',
      isDone: true,
      completedAt: DateTime.parse('2026-10-15T08:00:00Z'),
    ),
  ];

  group('Todo Flow Widget Tests', () {
    testWidgets('TodoListScreen renders sections, filter chips, and badges correctly',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/$podId/todos') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': sampleTodos.map((t) => t.toJson()).toList(),
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWithValue(currentUser),
            currentPodIdProvider.overrideWith(() => MockCurrentPodIdNotifier(podId)),
            activePodDetailProvider.overrideWith(() => MockActivePodDetailNotifier(mockPod)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TodoListScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // App bar & headers
      expect(find.text('Pod Tasks'), findsOneWidget);
      expect(find.text('Open (2)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsOneWidget);

      // Filter chips with dynamic counts
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Mine (1)'), findsOneWidget);
      expect(find.text('Alice Walker (1)'), findsOneWidget);
      expect(find.text('Shared (1)'), findsOneWidget);

      // Verify task cards and badges
      expect(find.text('Finish Flutter widget tests'), findsOneWidget);
      expect(find.text('Review Go API endpoints'), findsOneWidget);
      expect(find.text('Weekly check-in sync'), findsOneWidget);

      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Alice Walker'), findsAtLeastNWidgets(1));
      expect(find.text('Both'), findsOneWidget);

      // Test filtering by "Mine"
      await tester.tap(find.text('Mine (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Finish Flutter widget tests'), findsOneWidget);
      expect(find.text('Review Go API endpoints'), findsNothing);
      expect(find.text('Weekly check-in sync'), findsNothing);

      // Test filtering by "Shared"
      await tester.tap(find.text('Shared (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Weekly check-in sync'), findsOneWidget);
      expect(find.text('Finish Flutter widget tests'), findsNothing);
    });

    testWidgets('TodoListScreen optimistic toggle succeeds on 200 API response',
        (WidgetTester tester) async {
      bool patchCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/$podId/todos' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [sampleTodos[0].toJson()],
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/pods/$podId/todos/todo-mine' &&
                options.method == 'PATCH') {
              patchCalled = true;
              final body = options.data as Map<String, dynamic>;
              final updated = sampleTodos[0].copyWith(
                isDone: body['is_done'] as bool,
              );
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': updated.toJson(),
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWithValue(currentUser),
            currentPodIdProvider.overrideWith(() => MockCurrentPodIdNotifier(podId)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TodoListScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Open (1)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsNothing);

      // Find the checkbox for 'Finish Flutter widget tests'
      final checkboxFinder = find.byType(Checkbox);
      expect(checkboxFinder, findsOneWidget);

      final checkboxWidgetBefore = tester.widget<Checkbox>(checkboxFinder);
      expect(checkboxWidgetBefore.value, isFalse);

      // Tap the checkbox to toggle complete
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      expect(patchCalled, isTrue);
      expect(find.text('Open (0)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsOneWidget);
      expect(find.text('All open tasks completed! Tap + to add another.'), findsOneWidget);
    });

    testWidgets('TodoListScreen optimistic toggle rolls back and shows SnackBar on API error',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/$podId/todos' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [sampleTodos[0].toJson()],
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/pods/$podId/todos/todo-mine' &&
                options.method == 'PATCH') {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 500,
                    data: {
                      'data': null,
                      'meta': null,
                      'error': {'message': 'Server database failure', 'code': 500},
                    },
                  ),
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWithValue(currentUser),
            currentPodIdProvider.overrideWith(() => MockCurrentPodIdNotifier(podId)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TodoListScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Open (1)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsNothing);

      // Tap checkbox to toggle
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // Verified rollback: still 1 open todo, 0 completed
      expect(find.text('Open (1)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsNothing);

      // SnackBar displayed
      expect(
        find.text('Failed to update task. Changes reverted.'),
        findsOneWidget,
      );
    });

    testWidgets('AddEditTodoModal validates title and posts new task',
        (WidgetTester tester) async {
      bool postCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/$podId/todos' && options.method == 'POST') {
              postCalled = true;
              final body = options.data as Map<String, dynamic>;
              expect(body['title'], 'New Accountability Habit');
              expect(body['notes'], 'Check daily at 9am');
              expect(body['assigned_to'], partnerId);

              final created = TodoModel(
                id: 'new-todo-id',
                podId: podId,
                createdBy: currentUserId,
                assignedTo: partnerId,
                title: body['title'] as String,
                notes: body['notes'] as String?,
                isDone: false,
              );

              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': created.toJson(),
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWithValue(currentUser),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showAddEditTodoModal(
                        context,
                        podId: podId,
                        currentUserId: currentUserId,
                        partnerId: partnerId,
                        partnerName: 'Alice Walker',
                      );
                    },
                    child: const Text('Open Modal'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Add New Task'), findsOneWidget);

      // Attempt submit without title -> error validation
      await tester.tap(find.text('Add Task'));
      await tester.pumpAndSettle();
      expect(find.text('Title is required'), findsOneWidget);
      expect(postCalled, isFalse);

      // Enter title and notes
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));
      await tester.enterText(textFields.first, 'New Accountability Habit');
      await tester.enterText(textFields.at(1), 'Check daily at 9am');

      // Select partner assignee
      await tester.tap(find.text('Alice Walker'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('Add Task'));
      await tester.pumpAndSettle();

      expect(postCalled, isTrue);
      // Modal should be dismissed
      expect(find.text('Add New Task'), findsNothing);
    });

    testWidgets('TodoDetailScreen displays details, launches edit, and confirms delete',
        (WidgetTester tester) async {
      bool deleteCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/pods/$podId/todos/todo-mine' &&
                options.method == 'DELETE') {
              deleteCalled = true;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'message': 'todo deleted successfully'},
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
        initialLocation: AppRoutes.todoDetailPath,
        routes: [
          GoRoute(
            path: AppRoutes.todoDetailPath,
            builder: (context, state) => TodoDetailScreen(
              todo: sampleTodos[0],
              podId: podId,
            ),
          ),
          GoRoute(
            path: AppRoutes.todoListPath,
            builder: (context, state) => const Scaffold(
              body: Text('Returned to Todo List'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWithValue(currentUser),
            currentPodIdProvider.overrideWith(() => MockCurrentPodIdNotifier(podId)),
            activePodDetailProvider.overrideWith(() => MockActivePodDetailNotifier(mockPod)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Details rendered
      expect(find.text('Finish Flutter widget tests'), findsOneWidget);
      expect(find.text('Ensure 100% pass'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Due Date'), findsOneWidget);
      expect(find.text('2026-10-25'), findsOneWidget);
      expect(find.text('Assigned to Me'), findsOneWidget);

      // Tap Edit button -> opens modal
      await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      // Close modal
      await tester.tap(find.widgetWithIcon(IconButton, Icons.close_rounded));
      await tester.pumpAndSettle();

      // Tap Delete button -> shows AlertDialog
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Delete Task?'), findsOneWidget);
      expect(
        find.text('Are you sure you want to delete this task? This action cannot be undone.'),
        findsOneWidget,
      );

      // Confirm delete in dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deleteCalled, isTrue);
    });
  });
}
