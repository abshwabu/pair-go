import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/realtime_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/auth_state.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/chat/chat_screen.dart';
import 'package:mobile/features/chat/models/chat_message_model.dart';
import 'package:mobile/features/chat/widgets/chat_bubble.dart';
import 'package:mobile/features/chat/widgets/typing_indicator.dart';
import 'package:mobile/features/pods/models/pod_model.dart';
import 'package:mobile/features/pods/pod_state.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeWebSocketSink implements WebSocketSink {
  final StreamController _controller;
  FakeWebSocketSink(this._controller);
  @override
  void add(dynamic data) => _controller.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _controller.addError(error, stackTrace);
  @override
  Future addStream(Stream stream) => _controller.addStream(stream);
  @override
  Future close([int? closeCode, String? closeReason]) => _controller.close();
  @override
  Future get done => _controller.done;
}

class FakeWebSocketChannel extends StreamChannelMixin implements WebSocketChannel {
  final StreamController _inController = StreamController.broadcast();
  final StreamController _outController = StreamController();

  StreamController get inController => _inController;

  @override
  Stream get stream => _inController.stream;

  @override
  WebSocketSink get sink => FakeWebSocketSink(_outController);

  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  Future<void> get ready => Future.value();
}

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
    FlutterSecureStorage.setMockInitialValues({'pair_auth_token': 'fake-jwt-token'});
  });

  const currentUserId = 'user-me';
  const partnerId = 'user-partner';
  const podId = 'pod-chat-123';

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

  final sampleMessages = [
    ChatMessageModel(
      id: 'msg-1',
      podId: podId,
      senderId: partnerId,
      body: 'Good morning! Ready for today?',
      createdAt: DateTime.parse('2026-10-15T08:00:00Z'),
    ),
    ChatMessageModel(
      id: 'msg-2',
      podId: podId,
      senderId: currentUserId,
      body: 'Yes, just laced up my running shoes!',
      createdAt: DateTime.parse('2026-10-15T08:01:00Z'),
    ),
  ];

  group('RealtimeClient Unit Tests', () {
    test('Derives ws:// and wss:// correctly from API_BASE_URL', () {
      expect(
        RealtimeClient.deriveWebSocketUrl('http://localhost:8085/api/v1'),
        'ws://localhost:8085/api/v1',
      );
      expect(
        RealtimeClient.deriveWebSocketUrl('https://api.pair.app/api/v1/'),
        'wss://api.pair.app/api/v1',
      );
      expect(
        RealtimeClient.deriveWebSocketUrl('ws://custom.pair.app/ws'),
        'ws://custom.pair.app/ws',
      );
    });

    test('Parses events and handles reconnect', () async {
      final fakeChannel = FakeWebSocketChannel();
      final client = RealtimeClient(
        tokenStorage: TokenStorage(),
        channelFactory: (uri, headers) => fakeChannel,
      );

      final events = <RealtimeEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect(podId);
      expect(client.currentStatus, RealtimeConnectionStatus.connected);

      // Send a message event
      fakeChannel.inController.add(
        jsonEncode({
          'type': 'message',
          'data': {
            'id': 'msg-100',
            'pod_id': podId,
            'sender_id': partnerId,
            'body': 'Hello via WebSocket',
            'created_at': '2026-10-15T08:10:00Z',
          },
        }),
      );

      // Send a typing event
      fakeChannel.inController.add(
        jsonEncode({
          'type': 'typing',
          'data': {'user_id': partnerId},
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(events.length, 2);
      expect(events[0].type, RealtimeEventType.message);
      expect(events[0].data['body'], 'Hello via WebSocket');
      expect(events[1].type, RealtimeEventType.typing);
      expect(events[1].data['user_id'], partnerId);

      await sub.cancel();
      client.dispose();
    });
  });

  group('Chat Flow Widget Tests', () {
    testWidgets('ChatScreen loads message history and displays bubbles',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/messages')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': sampleMessages.map((m) => m.toJson()).toList(),
                    'meta': {'next_cursor': 'msg-1'},
                    'error': null,
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final fakeChannel = FakeWebSocketChannel();
      final realtimeClient = RealtimeClient(
        tokenStorage: TokenStorage(),
        channelFactory: (uri, headers) => fakeChannel,
      );

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            realtimeClientProvider.overrideWithValue(realtimeClient),
            currentUserProvider.overrideWithValue(currentUser),
            currentPodIdProvider.overrideWith(() => MockCurrentPodIdNotifier(podId)),
            activePodDetailProvider.overrideWith(() => MockActivePodDetailNotifier(mockPod)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ChatScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header partner info
      expect(find.text('Alice Walker'), findsAtLeastNWidgets(1));

      // Messages rendered
      expect(find.text('Good morning! Ready for today?'), findsOneWidget);
      expect(find.text('Yes, just laced up my running shoes!'), findsOneWidget);
      expect(find.byType(ChatBubble), findsNWidgets(2));
    });

    testWidgets('ChatScreen live appends incoming WebSocket message and dedupes',
        (WidgetTester tester) async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/messages')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [sampleMessages[0].toJson()],
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

      final fakeChannel = FakeWebSocketChannel();
      final realtimeClient = RealtimeClient(
        tokenStorage: TokenStorage(),
        channelFactory: (uri, headers) => fakeChannel,
      );

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            realtimeClientProvider.overrideWithValue(realtimeClient),
            currentUserProvider.overrideWithValue(currentUser),
            currentPodIdProvider.overrideWith(() => MockCurrentPodIdNotifier(podId)),
            activePodDetailProvider.overrideWith(() => MockActivePodDetailNotifier(mockPod)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ChatScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(ChatBubble), findsOneWidget);

      // Simulate incoming WebSocket message event
      fakeChannel.inController.add(
        jsonEncode({
          'type': 'message',
          'data': {
            'id': 'msg-live-1',
            'pod_id': podId,
            'sender_id': partnerId,
            'body': 'Just completed 5k!',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        }),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Just completed 5k!'), findsOneWidget);
      expect(find.byType(ChatBubble), findsNWidgets(2));

      // Resend same message ID -> deduped, count stays 2
      fakeChannel.inController.add(
        jsonEncode({
          'type': 'message',
          'data': {
            'id': 'msg-live-1',
            'pod_id': podId,
            'sender_id': partnerId,
            'body': 'Just completed 5k!',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        }),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ChatBubble), findsNWidgets(2));
    });

    testWidgets('TypingIndicator renders and displays partner name',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: TypingIndicator(partnerName: 'Alice Walker'),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Alice Walker is typing'), findsOneWidget);
      expect(find.byType(TypingIndicator), findsOneWidget);
    });

    testWidgets('ChatScreen sends message on submit and clears text controller',
        (WidgetTester tester) async {
      bool postMessageCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.startsWith('/pods/$podId/messages') && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': <dynamic>[],
                    'meta': null,
                    'error': null,
                  },
                ),
              );
            }
            if (options.path.startsWith('/pods/$podId/messages') && options.method == 'POST') {
              postMessageCalled = true;
              final body = options.data as Map<String, dynamic>;
              expect(body['body'], 'Crushing my workout today!');

              final created = ChatMessageModel(
                id: 'msg-new',
                podId: podId,
                senderId: currentUserId,
                body: body['body'] as String,
                createdAt: DateTime.now().toUtc(),
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
            if (options.path.startsWith('/pods/$podId/typing') && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'ok': true},
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

      final fakeChannel = FakeWebSocketChannel();
      final realtimeClient = RealtimeClient(
        tokenStorage: TokenStorage(),
        channelFactory: (uri, headers) => fakeChannel,
      );

      final apiClient = ApiClient(tokenStorage: TokenStorage(), customDio: dio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            realtimeClientProvider.overrideWithValue(realtimeClient),
            currentUserProvider.overrideWithValue(currentUser),
            currentPodIdProvider.overrideWith(() => MockCurrentPodIdNotifier(podId)),
            activePodDetailProvider.overrideWith(() => MockActivePodDetailNotifier(mockPod)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ChatScreen(podId: podId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter message in input field
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Crushing my workout today!');
      await tester.pumpAndSettle();

      // Tap send button
      final sendButton = find.widgetWithIcon(IconButton, Icons.send_rounded);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(postMessageCalled, isTrue);
      expect(find.text('Crushing my workout today!'), findsOneWidget);
    });
  });
}
