import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/auth_state.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/checkins/models/streak_model.dart';
import 'package:mobile/features/checkins/streak_detail_screen.dart';
import 'package:mobile/features/checkins/streak_provider.dart';
import 'package:mobile/features/checkins/streak_recovery_screen.dart';
import 'package:mobile/features/checkins/widgets/checkin_modal.dart';
import 'package:mobile/features/checkins/widgets/daily_checkin_card.dart';
import 'package:mobile/features/checkins/widgets/streak_badge.dart';
import 'package:mobile/features/pods/models/pod_model.dart';
import 'package:mobile/features/pods/pod_state.dart';

class MockActivePodDetailNotifier extends ActivePodDetailNotifier {
  final PodDetail? initialPod;
  MockActivePodDetailNotifier(this.initialPod);
  @override
  ActivePodDetailState build() => ActivePodDetailState(pod: initialPod);
}

class MockCurrentPodIdNotifier extends CurrentPodIdNotifier {
  final String? initialId;
  MockCurrentPodIdNotifier(this.initialId);
  @override
  String? build() => initialId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'pair_auth_token': 'test-token'});
  });

  const currentUserId = 'user-me';
  const partnerId = 'user-partner';
  const podId = 'pod-streak-123';

  final currentUser = const UserModel(
    id: currentUserId,
    email: 'me@pair.test',
    name: 'Me Myself',
    timezone: 'UTC',
    language: 'en',
  );

  final mockPod = PodDetail(
    id: podId,
    goalCategory: 'fitness',
    status: 'active',
    capacity: 2,
    members: const [
      PodMemberDetail(
        user: MemberPublicProfile(id: currentUserId, name: 'Me Myself'),
        goal: MemberGoalInfo(
          id: 'g-1',
          title: 'Daily 5k',
          category: 'fitness',
          pace: 'steady',
        ),
      ),
      PodMemberDetail(
        user: MemberPublicProfile(id: partnerId, name: 'Alice Walker'),
        goal: MemberGoalInfo(
          id: 'g-2',
          title: 'Morning Yoga',
          category: 'fitness',
          pace: 'steady',
        ),
      ),
    ],
    streak: const StreakSummary(currentStreak: 3, bestStreak: 7),
  );

  group('PodStreakNotifier Unit Tests', () {
    test('fetchStreak loads details and updates state', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/streak')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'current_streak': 5,
                      'best_streak': 12,
                      'last_check_in_date': '2026-10-14',
                      'me_checked_in_today': false,
                      'partner_checked_in_today': true,
                      'both_checked_in_today': false,
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
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );

      final notifier = container.read(podStreakProvider(podId).notifier);
      await notifier.fetchStreak(apiClient);

      final state = container.read(podStreakProvider(podId));
      expect(state.streak, isNotNull);
      expect(state.streak!.currentStreak, 5);
      expect(state.streak!.bestStreak, 12);
      expect(state.streak!.meCheckedInToday, isFalse);
      expect(state.streak!.partnerCheckedInToday, isTrue);
      expect(state.shouldShowDailyPrompt, isTrue);
    });

    test('checkIn updates streak and card state directly on 201', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/check-ins') &&
                options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {
                      'id': 'checkin-1',
                      'pod_id': podId,
                      'user_id': currentUserId,
                      'check_in_date': '2026-10-15',
                      'note': 'Ran 5k in morning',
                      'current_streak': 6,
                      'best_streak': 12,
                      'last_check_in_date': '2026-10-15',
                      'checked_in_today_by_both': true,
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
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );

      final notifier = container.read(podStreakProvider(podId).notifier);
      final ok = await notifier.checkIn(apiClient, note: 'Ran 5k in morning');
      expect(ok, isTrue);

      final state = container.read(podStreakProvider(podId));
      expect(state.streak!.currentStreak, 6);
      expect(state.streak!.bestStreak, 12);
      expect(state.streak!.meCheckedInToday, isTrue);
      expect(state.streak!.bothCheckedInToday, isTrue);
      expect(state.shouldShowDailyPrompt, isFalse);
    });

    test('checkIn handles 409 conflict gracefully as already checked in',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/check-ins') &&
                options.method == 'POST') {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'data': null,
                      'meta': null,
                      'error': {
                        'code': 'CONFLICT',
                        'message': 'already checked in for today',
                      },
                    },
                  ),
                ),
              );
            }
            if (options.path.startsWith('/pods/$podId/streak') &&
                options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'current_streak': 4,
                      'best_streak': 7,
                      'last_check_in_date': '2026-10-15',
                      'me_checked_in_today': true,
                      'partner_checked_in_today': false,
                      'both_checked_in_today': false,
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
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );

      final notifier = container.read(podStreakProvider(podId).notifier);
      final ok = await notifier.checkIn(apiClient);
      expect(ok, isTrue);

      final state = container.read(podStreakProvider(podId));
      expect(state.streak!.meCheckedInToday, isTrue);
      expect(state.streak!.currentStreak, 4);
    });

    test('nudgePartner succeeds and handles 429 rate limit with friendly copy',
        () async {
      bool return429 = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/nudge') &&
                options.method == 'POST') {
              if (return429) {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 429,
                      data: {
                        'data': null,
                        'meta': null,
                        'error': {
                          'code': 'RATE_LIMITED',
                          'message':
                              'you can only nudge your partner once every 6 hours',
                        },
                      },
                    ),
                  ),
                );
              }
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'message': 'nudge sent successfully'},
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
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );

      final notifier = container.read(podStreakProvider(podId).notifier);

      // 1. Success
      final ok = await notifier.nudgePartner(apiClient);
      expect(ok, isTrue);
      expect(container.read(podStreakProvider(podId)).nudgeSuccess, isTrue);

      // 2. 429 Rate limited
      return429 = true;
      final ok2 = await notifier.nudgePartner(apiClient);
      expect(ok2, isFalse);
      final state = container.read(podStreakProvider(podId));
      expect(state.hasNudgeRateLimited, isTrue);
      expect(state.nudgeStatus, 'You already nudged recently');
    });
  });

  group('Streak & Check-in Widgets and Screen Tests', () {
    testWidgets('StreakBadge displays flame icon and current streak and triggers onTap',
        (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: StreakBadge(
                podId: podId,
                fallbackCurrentStreak: 5,
                fallbackBestStreak: 10,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      expect(find.text('5 streak'), findsOneWidget);
      expect(find.text('Best: 10'), findsOneWidget);

      await tester.tap(find.byType(StreakBadge));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('DailyCheckinCard shows when meCheckedInToday is false and hides on dismiss',
        (WidgetTester tester) async {
      final dio = Dio();
      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );

      // Seed state: meCheckedInToday = false
      final notifier = container.read(podStreakProvider(podId).notifier);
      notifier.state = PodStreakState(
        streak: const PodStreakDetails(
          currentStreak: 3,
          bestStreak: 7,
          meCheckedInToday: false,
          partnerCheckedInToday: true,
          bothCheckedInToday: false,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: DailyCheckinCard(
                podId: podId,
                partnerName: 'Alice',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Daily Check-in'), findsOneWidget);
      expect(find.textContaining('Alice already checked in!'), findsOneWidget);

      // Tap dismiss icon
      final dismissButton = find.byTooltip('Dismiss');
      expect(dismissButton, findsOneWidget);
      await tester.tap(dismissButton);
      await tester.pump();

      expect(find.text('Daily Check-in'), findsNothing);
    });

    testWidgets('CheckInModal submits check-in and updates streak badge directly',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/check-ins') &&
                options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {
                      'id': 'checkin-modal-1',
                      'pod_id': podId,
                      'user_id': currentUserId,
                      'check_in_date': '2026-10-15',
                      'note': 'Hit 10k steps!',
                      'current_streak': 4,
                      'best_streak': 7,
                      'last_check_in_date': '2026-10-15',
                      'checked_in_today_by_both': false,
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
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );

      container.read(podStreakProvider(podId).notifier).state =
          const PodStreakState(
        streak: PodStreakDetails(
          currentStreak: 3,
          bestStreak: 7,
          meCheckedInToday: false,
          partnerCheckedInToday: false,
          bothCheckedInToday: false,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => CheckInModal.show(
                    context,
                    podId: podId,
                    partnerName: 'Alice',
                  ),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open Modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Daily Check-in'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Enter note
      await tester.enterText(find.byType(TextField), 'Hit 10k steps!');
      await tester.pump();

      // Tap confirm check-in
      await tester.tap(find.text('Confirm Check-in'));
      await tester.pumpAndSettle();

      // Modal dismissed and state updated directly
      expect(find.text('Daily Check-in'), findsNothing);
      final updatedState = container.read(podStreakProvider(podId));
      expect(updatedState.streak!.currentStreak, 4);
      expect(updatedState.streak!.meCheckedInToday, isTrue);
    });

    testWidgets('StreakDetailScreen displays stats, distinguishes history, and shows recovery banner when broken',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/streak')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'current_streak': 0,
                      'best_streak': 8,
                      'last_check_in_date': '2026-10-12',
                      'me_checked_in_today': false,
                      'partner_checked_in_today': false,
                      'both_checked_in_today': false,
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path.startsWith('/pods/$podId/check-ins')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'date': '2026-10-14',
                        'member_ids': [currentUserId, partnerId],
                        'both_checked_in': true,
                      },
                      {
                        'date': '2026-10-13',
                        'member_ids': [currentUserId],
                        'both_checked_in': false,
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
            home: const StreakDetailScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Screen Header
      expect(find.text('Streak & Check-ins'), findsOneWidget);

      // Broken streak banner (current == 0 and best > 0)
      expect(find.text('Streak Paused'), findsOneWidget);
      expect(find.text('View Recovery Options & Nudge'), findsOneWidget);

      // Streak Stats
      expect(find.text('0'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);

      // Distinguishes both completed vs 1 of 2
      expect(find.text('Both Completed'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('2026-10-14'), findsOneWidget);
      expect(find.text('2026-10-13'), findsOneWidget);
    });

    testWidgets('StreakRecoveryScreen only displays recovery view in broken state and handles nudge rate limit',
        (WidgetTester tester) async {
      bool isBroken = false;
      bool return429 = false;

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/streak')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'current_streak': isBroken ? 0 : 5,
                      'best_streak': 10,
                      'last_check_in_date': '2026-10-14',
                      'me_checked_in_today': false,
                      'partner_checked_in_today': false,
                      'both_checked_in_today': false,
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path.startsWith('/pods/$podId/nudge')) {
              if (return429) {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 429,
                      data: {
                        'data': null,
                        'meta': null,
                        'error': {
                          'code': 'RATE_LIMITED',
                          'message': 'you can only nudge once per 6 hours',
                        },
                      },
                    ),
                  ),
                );
              }
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'message': 'nudge sent successfully'},
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

      // 1. Non-broken state (current_streak == 5)
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
            home: const StreakRecoveryScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Your Streak is Active!'), findsOneWidget);
      expect(find.text('Nudge your partner'), findsNothing);

      // Clean up widget tree
      await tester.pumpWidget(const SizedBox());

      // 2. Broken streak state (current_streak == 0, best_streak == 10)
      isBroken = true;
      return429 = true;

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
            home: const StreakRecoveryScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Displays encouraging copy & record
      expect(find.text('Let\'s Get Back on Track!'), findsOneWidget);
      expect(find.text('10 Consecutive Days'), findsOneWidget);
      expect(find.text('Nudge your partner'), findsOneWidget);

      // Tap Nudge button when rate limited
      final nudgeButton = find.text('Nudge your partner');
      await tester.ensureVisible(nudgeButton);
      await tester.tap(nudgeButton);
      await tester.pumpAndSettle();

      // Displays friendly message
      expect(find.text('You already nudged recently'), findsOneWidget);
    });
  });
}
