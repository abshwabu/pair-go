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
import 'package:mobile/features/matching/match_confirmed_screen.dart';
import 'package:mobile/features/matching/match_pending_screen.dart';
import 'package:mobile/features/matching/match_proposal_screen.dart';
import 'package:mobile/features/matching/matching_state_provider.dart';
import 'package:mobile/features/matching/models/matching_state_model.dart';
import 'package:mobile/features/pods/models/pod_model.dart';
import 'package:mobile/features/pods/pod_state.dart';

class MockPodNotifier extends ActivePodDetailNotifier {
  final PodDetail? _pod;
  MockPodNotifier(this._pod);

  @override
  ActivePodDetailState build() => ActivePodDetailState(
        isLoading: false,
        pod: _pod,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Routing Rules: routeForState', () {
    test('routes to /goal-category when state is none', () {
      const state = MatchingStateModel(status: MatchingStatus.none);
      expect(routeForState(state), AppRoutes.goalCategoryPath);
    });

    test('routes to /finding-match when state is searching', () {
      const state = MatchingStateModel(status: MatchingStatus.searching);
      expect(routeForState(state), AppRoutes.findingMatchPath);
    });

    test('routes to /match-proposal when proposed and my_response is pending', () {
      final state = MatchingStateModel(
        status: MatchingStatus.proposed,
        proposal: MatchProposalModel(
          id: 'prop-1',
          myResponse: 'pending',
          expiresAt: DateTime.now().add(const Duration(hours: 12)),
          partner: const PartnerProfileModel(
            name: 'Sarah Connor',
            timezone: 'UTC',
            utcOffsetHours: 3,
          ),
          partnerGoal: const PartnerGoalModel(
            title: 'Read 20 pages daily',
            category: 'read',
            pace: 'steady',
          ),
        ),
      );
      expect(routeForState(state), AppRoutes.matchProposalPath);
    });

    test('routes to /match-pending when proposed and my_response is accepted', () {
      final state = MatchingStateModel(
        status: MatchingStatus.proposed,
        proposal: MatchProposalModel(
          id: 'prop-1',
          myResponse: 'accepted',
          expiresAt: DateTime.now().add(const Duration(hours: 12)),
          partner: const PartnerProfileModel(
            name: 'Sarah Connor',
            timezone: 'UTC',
            utcOffsetHours: 3,
          ),
          partnerGoal: const PartnerGoalModel(
            title: 'Read 20 pages daily',
            category: 'read',
            pace: 'steady',
          ),
        ),
      );
      expect(routeForState(state), AppRoutes.matchPendingPath);
    });

    test('routes to /pod-home when matched (outside active matching transition)', () {
      const state = MatchingStateModel(
        status: MatchingStatus.matched,
        podId: 'pod-123',
      );
      expect(
        routeForState(state, inMatchingFlow: false),
        AppRoutes.podHomePath,
      );
    });

    test('routes to /match-confirmed when matched inside active matching transition', () {
      const state = MatchingStateModel(
        status: MatchingStatus.matched,
        podId: 'pod-123',
      );
      expect(
        routeForState(state, inMatchingFlow: true),
        AppRoutes.matchConfirmedPath,
      );
    });
  });

  group('MatchingStateNotifier Provider Unit Tests', () {
    test('transition from searching to proposed', () async {
      int fetchCount = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              fetchCount++;
              if (fetchCount == 1) {
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {
                        'state': 'searching',
                        'request_id': 'req-1',
                        'pod_id': null,
                        'proposal': null,
                      },
                      'meta': null,
                      'error': null,
                    },
                  ),
                );
              } else {
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'data': {
                        'state': 'proposed',
                        'request_id': 'req-1',
                        'pod_id': null,
                        'proposal': {
                          'id': 'prop-100',
                          'my_response': 'pending',
                          'expires_at': DateTime.now()
                              .add(const Duration(hours: 12))
                              .toIso8601String(),
                          'partner': {
                            'name': 'Bob Smith',
                            'avatar_url': null,
                            'timezone': 'UTC',
                            'utc_offset_hours': 2,
                          },
                          'partner_goal': {
                            'title': 'Learn Flutter',
                            'category': 'study',
                            'pace': 'steady',
                          },
                        },
                      },
                      'meta': null,
                      'error': null,
                    },
                  ),
                );
              }
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
      addTearDown(container.dispose);

      // Initial state is searching
      final initial = await container.read(matchingStateProvider.future);
      expect(initial.isSearching, isTrue);

      // Refresh transitions to proposed
      final updated =
          await container.read(matchingStateProvider.notifier).refresh();
      expect(updated.isProposed, isTrue);
      expect(updated.proposal?.id, 'prop-100');
      expect(updated.proposal?.partner.name, 'Bob Smith');
      expect(updated.proposal?.isPending, isTrue);
    });

    test('accept with partner pending returns proposed and my_response accepted', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-100',
                        'my_response': 'pending',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'Bob Smith',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 2,
                        },
                        'partner_goal': {
                          'title': 'Learn Flutter',
                          'category': 'study',
                          'pace': 'steady',
                        },
                      },
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/matching/proposals/prop-100/accept') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-100',
                        'my_response': 'accepted',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'Bob Smith',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 2,
                        },
                        'partner_goal': {
                          'title': 'Learn Flutter',
                          'category': 'study',
                          'pace': 'steady',
                        },
                      },
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
      addTearDown(container.dispose);

      await container.read(matchingStateProvider.future);
      final acceptedState =
          await container.read(matchingStateProvider.notifier).accept('prop-100');

      expect(acceptedState.isProposed, isTrue);
      expect(acceptedState.proposal?.isAccepted, isTrue);
      expect(acceptedState.isMatched, isFalse);
    });

    test('accept with partner already accepted returns matched and pod_id', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-200',
                        'my_response': 'pending',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'Alice Wonder',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 0,
                        },
                        'partner_goal': {
                          'title': 'Exercise daily',
                          'category': 'fitness',
                          'pace': 'steady',
                        },
                      },
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/matching/proposals/prop-200/accept') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'matched',
                      'request_id': 'req-1',
                      'pod_id': 'pod-matched-999',
                      'proposal': null,
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
      addTearDown(container.dispose);

      await container.read(matchingStateProvider.future);
      final acceptedState =
          await container.read(matchingStateProvider.notifier).accept('prop-200');

      expect(acceptedState.isMatched, isTrue);
      expect(acceptedState.podId, 'pod-matched-999');
      expect(acceptedState.proposal, isNull);
    });

    test('reject returns to searching with banner flag', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-300',
                        'my_response': 'pending',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'David',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 1,
                        },
                        'partner_goal': {
                          'title': 'Drink water',
                          'category': 'health',
                          'pace': 'relaxed',
                        },
                      },
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/matching/proposals/prop-300/reject') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'searching',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': null,
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
      addTearDown(container.dispose);

      await container.read(matchingStateProvider.future);
      final rejectedState =
          await container.read(matchingStateProvider.notifier).reject('prop-300');

      expect(rejectedState.isSearching, isTrue);
      expect(
        rejectedState.rejectionBannerMessage,
        "Your last match didn't work out, we're finding you someone new.",
      );
    });

    test('handles 409 proposal_closed by refreshing state and rethrowing', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'searching',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': null,
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/matching/proposals/prop-expired/accept') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 409,
                  data: {
                    'data': null,
                    'meta': null,
                    'error': {
                      'code': 'proposal_closed',
                      'message': 'match proposal is no longer pending',
                    },
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
      addTearDown(container.dispose);

      await container.read(matchingStateProvider.future);

      try {
        await container
            .read(matchingStateProvider.notifier)
            .accept('prop-expired');
        fail('expected ApiException with code proposal_closed');
      } on ApiException catch (e) {
        expect(e.code, 'proposal_closed');
      }

      // State was refreshed to searching
      final refreshed = container.read(matchingStateProvider).value;
      expect(refreshed?.isSearching, isTrue);
    });
  });

  group('Widget Tests: MatchProposalScreen & Flow Transitions', () {
    testWidgets(
        'Tapping "Let\'s go" when partner is pending routes to /match-pending and NEVER to /pod-home',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-pending-test',
                        'my_response': 'pending',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'Jessica Jones',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 3,
                        },
                        'partner_goal': {
                          'title': 'Read 1 book a month',
                          'category': 'reading',
                          'pace': 'steady',
                        },
                      },
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/matching/proposals/prop-pending-test/accept') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-pending-test',
                        'my_response': 'accepted',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'Jessica Jones',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 3,
                        },
                        'partner_goal': {
                          'title': 'Read 1 book a month',
                          'category': 'reading',
                          'pace': 'steady',
                        },
                      },
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
        initialLocation: AppRoutes.matchProposalPath,
        routes: [
          GoRoute(
            path: AppRoutes.matchProposalPath,
            builder: (context, state) => const MatchProposalScreen(),
          ),
          GoRoute(
            path: AppRoutes.matchPendingPath,
            builder: (context, state) => const Scaffold(
              body: Text('Match Pending Destination'),
            ),
          ),
          GoRoute(
            path: AppRoutes.podHomePath,
            builder: (context, state) => const Scaffold(
              body: Text('Pod Home Destination'),
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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify prominent partner card elements
      expect(find.text('Jessica Jones'), findsOneWidget);
      expect(find.text('Read 1 book a month'), findsOneWidget);
      expect(find.text('READING'), findsOneWidget);
      expect(find.text('STEADY'), findsOneWidget);
      expect(find.text("Let's go"), findsOneWidget);
      expect(find.text('Pass'), findsOneWidget);

      // Tap "Let's go"
      await tester.tap(find.text("Let's go"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Verifies it routes to match-pending and NEVER to pod-home
      expect(find.text('Match Pending Destination'), findsOneWidget);
      expect(find.text('Pod Home Destination'), findsNothing);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'Tapping "Let\'s go" when partner also accepted routes to match-confirmed and NOT directly to pod-home',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-confirmed-test',
                        'my_response': 'pending',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'Peter Parker',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 0,
                        },
                        'partner_goal': {
                          'title': 'Daily Exercise',
                          'category': 'fitness',
                          'pace': 'steady',
                        },
                      },
                    },
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path == '/matching/proposals/prop-confirmed-test/accept') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'matched',
                      'request_id': 'req-1',
                      'pod_id': 'pod-final-777',
                      'proposal': null,
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
        initialLocation: AppRoutes.matchProposalPath,
        routes: [
          GoRoute(
            path: AppRoutes.matchProposalPath,
            builder: (context, state) => const MatchProposalScreen(),
          ),
          GoRoute(
            path: AppRoutes.matchConfirmedPath,
            builder: (context, state) => const Scaffold(
              body: Text('Match Confirmed Destination'),
            ),
          ),
          GoRoute(
            path: AppRoutes.podHomePath,
            builder: (context, state) => const Scaffold(
              body: Text('Pod Home Destination'),
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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Peter Parker'), findsOneWidget);

      // Tap "Let's go"
      await tester.tap(find.text("Let's go"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Verifies it routes to match-confirmed and NOT directly to pod-home
      expect(find.text('Match Confirmed Destination'), findsOneWidget);
      expect(find.text('Pod Home Destination'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'MatchConfirmedScreen "Go to your pod" is the only path that routes to pod-home',
        (WidgetTester tester) async {
      const mockPod = PodDetail(
        id: 'pod-final-777',
        goalCategory: 'fitness',
        status: 'active',
        capacity: 2,
        members: [
          PodMemberDetail(
            user: MemberPublicProfile(id: 'u-me', name: 'John Doe'),
            goal: MemberGoalInfo(
              id: 'g-1',
              title: 'Run 5k',
              category: 'fitness',
              pace: 'steady',
            ),
          ),
          PodMemberDetail(
            user: MemberPublicProfile(id: 'u-partner', name: 'Peter Parker'),
            goal: MemberGoalInfo(
              id: 'g-2',
              title: 'Daily Exercise',
              category: 'fitness',
              pace: 'steady',
            ),
          ),
        ],
        streak: StreakSummary(currentStreak: 0, bestStreak: 0),
      );

      final dio = Dio();
      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      final router = GoRouter(
        initialLocation: AppRoutes.matchConfirmedPath,
        routes: [
          GoRoute(
            path: AppRoutes.matchConfirmedPath,
            builder: (context, state) =>
                const MatchConfirmedScreen(podId: 'pod-final-777'),
          ),
          GoRoute(
            path: AppRoutes.podHomePath,
            builder: (context, state) => const Scaffold(
              body: Text('Reached Pod Home'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentUserProvider.overrideWithValue(
              const UserModel(
                id: 'u-me',
                email: 'john@example.com',
                name: 'John Doe',
                timezone: 'UTC',
              ),
            ),
            activePodDetailProvider
                .overrideWith(() => MockPodNotifier(mockPod)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("You're paired!"), findsOneWidget);
      expect(find.text('Go to your pod'), findsOneWidget);

      // Tap "Go to your pod"
      await tester.ensureVisible(find.text('Go to your pod'));
      await tester.tap(find.text('Go to your pod'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Reached Pod Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'MatchPendingScreen displays partner first name, calm waiting animation, and cancel text button',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/matching/current') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'state': 'proposed',
                      'request_id': 'req-1',
                      'pod_id': null,
                      'proposal': {
                        'id': 'prop-pending-view',
                        'my_response': 'accepted',
                        'expires_at': DateTime.now()
                            .add(const Duration(hours: 12))
                            .toIso8601String(),
                        'partner': {
                          'name': 'Maya Lin',
                          'avatar_url': null,
                          'timezone': 'UTC',
                          'utc_offset_hours': 1,
                        },
                        'partner_goal': {
                          'title': 'Design daily',
                          'category': 'design',
                          'pace': 'steady',
                        },
                      },
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
        initialLocation: AppRoutes.matchPendingPath,
        routes: [
          GoRoute(
            path: AppRoutes.matchPendingPath,
            builder: (context, state) => const MatchPendingScreen(),
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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Headline should use partner first name
      expect(find.text('Waiting for Maya to confirm'), findsOneWidget);
      expect(find.text('Design daily'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel button opens confirmation dialog
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Stop looking?'), findsOneWidget);
      expect(find.text("You'll leave the matching queue."), findsOneWidget);
      expect(find.text('Keep waiting'), findsOneWidget);
      expect(find.text('Leave queue'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Keep waiting'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pumpWidget(const SizedBox());
    });
  });
}
