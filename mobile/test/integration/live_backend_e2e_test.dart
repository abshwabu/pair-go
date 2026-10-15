import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/network/realtime_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/features/auth/models/user_model.dart';
import 'package:mobile/features/chat/models/chat_message_model.dart';
import 'package:mobile/features/goals/models/goal_model.dart';
import 'package:mobile/features/matching/models/matching_request_model.dart';
import 'package:mobile/features/pods/models/pod_model.dart';
import 'package:mobile/features/todos/models/todo_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late TokenStorage tokenStorage;
  late ApiClient apiClient;

  setUp(() {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    tokenStorage = TokenStorage();
    apiClient = ApiClient(
      tokenStorage: tokenStorage,
      baseUrl: 'http://localhost:8085/api/v1',
    );
  });

  group('Live Go Backend End-to-End Integration', () {
    test('Full onboarding flow against live Go backend', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'e2e_user_$uniqueSuffix@pair.test';
      final testPassword = 'StrongPassword123!';

      // 1. Register new user
      final registerRes = await apiClient.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'name': 'E2E Tester',
          'email': testEmail,
          'password': testPassword,
          'timezone': 'UTC',
        },
      );

      expect(registerRes.data['token'], isNotNull);
      final rawToken = registerRes.data['token'] as String;
      expect(rawToken.isNotEmpty, isTrue);

      final user = UserModel.fromJson(registerRes.data['user']);
      expect(user.name, 'E2E Tester');
      expect(user.email, testEmail);

      // 2. Save token to TokenStorage
      await tokenStorage.saveToken(rawToken);
      expect(await tokenStorage.hasToken(), isTrue);

      // 3. Validate session via /auth/me
      final meRes = await apiClient.get<Map<String, dynamic>>('/auth/me');
      final fetchedUser = UserModel.fromJson(meRes.data);
      expect(fetchedUser.id, user.id);
      expect(fetchedUser.email, testEmail);

      // 4. Update profile via PATCH /profile
      final updateRes = await apiClient.patch<Map<String, dynamic>>(
        '/profile',
        data: {
          'name': 'E2E Tester Updated',
          'timezone': 'America/New_York',
        },
      );
      final updatedUser = UserModel.fromJson(updateRes.data);
      expect(updatedUser.name, 'E2E Tester Updated');
      expect(updatedUser.timezone, 'America/New_York');

      // 5. Create goal via POST /goals
      final goalRes = await apiClient.post<Map<String, dynamic>>(
        '/goals',
        data: {
          'category': 'fitness',
          'title': 'E2E Marathon Training',
          'target_description': 'Run 10km three times a week',
          'pace': 'steady',
        },
      );
      final createdGoal = GoalModel.fromJson(goalRes.data);
      expect(createdGoal.id.isNotEmpty, isTrue);
      expect(createdGoal.category, 'fitness');
      expect(createdGoal.title, 'E2E Marathon Training');
      expect(createdGoal.pace, 'steady');

      // 6. Query pods via GET /pods
      final podsRes = await apiClient.get<dynamic>('/pods');
      expect(podsRes.data, isA<List>());

      // 7. Login with newly created credentials
      await tokenStorage.deleteToken();
      expect(await tokenStorage.hasToken(), isFalse);

      final loginRes = await apiClient.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': testEmail,
          'password': testPassword,
        },
      );
      expect(loginRes.data['token'], isNotNull);
      final loginUser = UserModel.fromJson(loginRes.data['user']);
      expect(loginUser.id, user.id);
      expect(loginUser.email, testEmail);
    });

    test('Full matching to pod home, leave pod, and block partner flow', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;

      // 1. Register User A
      final userAStorage = TokenStorage();
      final userAApi = ApiClient(
        tokenStorage: userAStorage,
        baseUrl: 'http://localhost:8085/api/v1',
      );

      final userAReg = await userAApi.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'name': 'User Alpha',
          'email': 'alpha_$uniqueSuffix@pair.test',
          'password': 'Password123!',
          'timezone': 'UTC',
        },
      );
      final tokenA = userAReg.data['token'] as String;
      final userAId = (userAReg.data['user'] as Map<String, dynamic>)['id'] as String;
      await userAStorage.saveToken(tokenA);

      // Create Goal for User A
      final goalARes = await userAApi.post<Map<String, dynamic>>(
        '/goals',
        data: {
          'category': 'read',
          'title': 'Read Sci-Fi Books',
          'target_description': '1 chapter daily',
          'pace': 'steady',
        },
      );
      final goalA = GoalModel.fromJson(goalARes.data);

      // User A submits match request
      final matchARes = await userAApi.post<Map<String, dynamic>>(
        '/matching/request',
        data: {
          'goal_id': goalA.id,
          'timezone_tolerance_hours': 5,
        },
      );
      final reqA = MatchingRequestModel.fromJson(matchARes.data);
      expect(reqA.status, 'open');

      // Test Cancel Match Request and Re-creation
      await userAApi.delete<Map<String, dynamic>>('/matching/request/${reqA.id}');
      final checkCancelRes = await userAApi.get<Map<String, dynamic>>('/matching/request/${reqA.id}');
      final cancelledReq = MatchingRequestModel.fromJson(checkCancelRes.data);
      expect(cancelledReq.status, 'cancelled');

      // Re-create match request for User A
      final newMatchARes = await userAApi.post<Map<String, dynamic>>(
        '/matching/request',
        data: {
          'goal_id': goalA.id,
          'timezone_tolerance_hours': 5,
        },
      );
      final newReqA = MatchingRequestModel.fromJson(newMatchARes.data);
      expect(newReqA.status, 'open');

      // 2. Register User B
      final userBStorage = TokenStorage();
      final userBApi = ApiClient(
        tokenStorage: userBStorage,
        baseUrl: 'http://localhost:8085/api/v1',
      );

      final userBReg = await userBApi.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'name': 'User Beta',
          'email': 'beta_$uniqueSuffix@pair.test',
          'password': 'Password123!',
          'timezone': 'UTC',
        },
      );
      final tokenB = userBReg.data['token'] as String;
      final userBId = (userBReg.data['user'] as Map<String, dynamic>)['id'] as String;
      await userBStorage.saveToken(tokenB);

      // Create Goal for User B
      final goalBRes = await userBApi.post<Map<String, dynamic>>(
        '/goals',
        data: {
          'category': 'read',
          'title': 'Read Dune Chronicles',
          'target_description': 'Finish by end of month',
          'pace': 'steady',
        },
      );
      final goalB = GoalModel.fromJson(goalBRes.data);

      // User B submits match request (matches immediately with User A!)
      final matchBRes = await userBApi.post<Map<String, dynamic>>(
        '/matching/request',
        data: {
          'goal_id': goalB.id,
          'timezone_tolerance_hours': 5,
        },
      );
      final reqB = MatchingRequestModel.fromJson(matchBRes.data);

      // Wait a moment for worker to complete transaction if asynchronous
      String? matchedPodId = reqB.podId;
      if (matchedPodId == null || matchedPodId.isEmpty) {
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 300));
          final poll = await userBApi.get<Map<String, dynamic>>('/matching/request/${reqB.id}');
          final pollReq = MatchingRequestModel.fromJson(poll.data);
          if (pollReq.isMatched) {
            matchedPodId = pollReq.podId;
            break;
          }
        }
      }

      expect(matchedPodId, isNotNull);
      expect(matchedPodId!.isNotEmpty, isTrue);

      // 3. User A checks request status -> matched!
      final pollA = await userAApi.get<Map<String, dynamic>>('/matching/request/${newReqA.id}');
      final pollReqA = MatchingRequestModel.fromJson(pollA.data);
      expect(pollReqA.status, 'matched');
      expect(pollReqA.podId, matchedPodId);

      // 4. User A fetches pod detail via GET /pods/{id}
      final podRes = await userAApi.get<Map<String, dynamic>>('/pods/$matchedPodId');
      final podDetail = PodDetail.fromJson(podRes.data);
      expect(podDetail.id, matchedPodId);
      expect(podDetail.goalCategory, 'read');
      expect(podDetail.status, 'active');
      expect(podDetail.members.length, 2);

      final partner = podDetail.partner(userAId);
      expect(partner, isNotNull);
      expect(partner!.user.id, userBId);
      expect(partner.user.name, 'User Beta');
      expect(partner.goal.title, 'Read Dune Chronicles');

      // 5. Test Todo CRUD in active pod
      // 5a. User A creates a personal todo
      final createTodoResA = await userAApi.post<Map<String, dynamic>>(
        '/pods/$matchedPodId/todos',
        data: {
          'title': 'Read Chapters 1 to 3',
          'notes': 'Pages 1-85',
          'due_date': '2026-10-25',
          'assigned_to': userAId,
        },
      );
      final todoA = TodoModel.fromJson(createTodoResA.data);
      expect(todoA.id.isNotEmpty, isTrue);
      expect(todoA.title, 'Read Chapters 1 to 3');
      expect(todoA.notes, 'Pages 1-85');
      expect(todoA.dueDate, '2026-10-25');
      expect(todoA.assignedTo, userAId);
      expect(todoA.isDone, isFalse);

      // 5b. User B creates a shared todo
      final createTodoResB = await userBApi.post<Map<String, dynamic>>(
        '/pods/$matchedPodId/todos',
        data: {
          'title': 'Weekly Chapter Discussion',
          'notes': 'Discuss worldbuilding on Saturday',
          'assigned_to': null,
        },
      );
      final todoB = TodoModel.fromJson(createTodoResB.data);
      expect(todoB.title, 'Weekly Chapter Discussion');
      expect(todoB.isShared, isTrue);

      // 5c. User A lists todos via GET /pods/{pod}/todos
      final listRes = await userAApi.get<dynamic>('/pods/$matchedPodId/todos');
      final listData = (listRes.data as List)
          .map((item) => TodoModel.fromJson(item as Map<String, dynamic>))
          .toList();
      expect(listData.length, 2);

      // 5d. User A toggles completion via PATCH /pods/{pod}/todos/{todo}
      final patchRes = await userAApi.patch<Map<String, dynamic>>(
        '/pods/$matchedPodId/todos/${todoA.id}',
        data: {'is_done': true},
      );
      final patchedTodoA = TodoModel.fromJson(patchRes.data);
      expect(patchedTodoA.isDone, isTrue);
      expect(patchedTodoA.completedAt, isNotNull);

      // 5e. User B updates the shared todo
      final updateRes = await userBApi.patch<Map<String, dynamic>>(
        '/pods/$matchedPodId/todos/${todoB.id}',
        data: {
          'title': 'Weekly Discussion on Sunday',
          'due_date': '2026-10-26',
        },
      );
      final updatedTodoB = TodoModel.fromJson(updateRes.data);
      expect(updatedTodoB.title, 'Weekly Discussion on Sunday');
      expect(updatedTodoB.dueDate, '2026-10-26');

      // 5f. User A deletes their completed todo via DELETE /pods/{pod}/todos/{todo}
      final delRes = await userAApi.delete<Map<String, dynamic>>(
        '/pods/$matchedPodId/todos/${todoA.id}',
      );
      expect(delRes.data['message'], contains('deleted'));

      // 5g. Verify list now has 1 todo
      final listAfterDel = await userAApi.get<dynamic>('/pods/$matchedPodId/todos');
      expect((listAfterDel.data as List).length, 1);

      // 5h. Realtime Chat & Attachments via WebSocket and REST
      final clientA = RealtimeClient(
        tokenStorage: userAStorage,
        baseUrl: 'http://localhost:8085/api/v1',
      );
      final clientB = RealtimeClient(
        tokenStorage: userBStorage,
        baseUrl: 'http://localhost:8085/api/v1',
      );

      final eventsA = <RealtimeEvent>[];
      final eventsB = <RealtimeEvent>[];
      final subA = clientA.events.listen(eventsA.add);
      final subB = clientB.events.listen(eventsB.add);

      // Connect both users to WebSocket hub
      await clientA.connect(matchedPodId);
      await clientB.connect(matchedPodId);
      expect(clientA.currentStatus, RealtimeConnectionStatus.connected);
      expect(clientB.currentStatus, RealtimeConnectionStatus.connected);

      // User A sends message via REST
      final sendMsgResA = await userAApi.post<Map<String, dynamic>>(
        '/pods/$matchedPodId/messages',
        data: {'body': 'Hello partner, let us reach 10k steps today!'},
      );
      final sentMsgA = ChatMessageModel.fromJson(sendMsgResA.data);
      expect(sentMsgA.body, 'Hello partner, let us reach 10k steps today!');
      expect(sentMsgA.senderId, userAId);

      // User B receives the message event live over WebSocket
      await Future.delayed(const Duration(milliseconds: 300));
      expect(
        eventsB.any((e) =>
            e.type == RealtimeEventType.message &&
            e.data['body'] == sentMsgA.body),
        isTrue,
      );

      // User B posts typing indicator
      await userBApi.post<dynamic>('/pods/$matchedPodId/typing');
      await Future.delayed(const Duration(milliseconds: 300));
      expect(
        eventsA.any((e) =>
            e.type == RealtimeEventType.typing &&
            e.data['user_id'] == userBId),
        isTrue,
      );

      // User A uploads photo attachment proof
      final tempDir = await Directory.systemTemp.createTemp('pair_attachment_test');
      final testFile = File('${tempDir.path}/proof.jpg');
      await testFile.writeAsBytes([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      ]);

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(testFile.path, filename: 'proof.jpg'),
      });
      final uploadRes = await userAApi.post<Map<String, dynamic>>(
        '/pods/$matchedPodId/attachments',
        data: formData,
      );
      expect(uploadRes.data['url'], isNotNull);
      final attachmentUrl = uploadRes.data['url'] as String;
      expect(attachmentUrl.isNotEmpty, isTrue);

      // User A sends message with attachment
      final sendMsgWithAttachmentRes = await userAApi.post<Map<String, dynamic>>(
        '/pods/$matchedPodId/messages',
        data: {
          'body': 'Here is my workout photo proof!',
          'attachment_url': attachmentUrl,
        },
      );
      final msgWithAttachment =
          ChatMessageModel.fromJson(sendMsgWithAttachmentRes.data);
      expect(msgWithAttachment.attachmentUrl, attachmentUrl);

      // User B receives message with attachment over WebSocket
      await Future.delayed(const Duration(milliseconds: 300));
      expect(
        eventsB.any((e) =>
            e.type == RealtimeEventType.message &&
            e.data['attachment_url'] == attachmentUrl),
        isTrue,
      );

      // Verify cursor pagination on GET /pods/{pod}/messages
      final historyRes =
          await userAApi.get<dynamic>('/pods/$matchedPodId/messages?limit=1');
      expect((historyRes.data as List).length, 1);
      final nextCursor = historyRes.meta?['next_cursor'] as String?;
      expect(nextCursor, isNotNull);

      final nextHistoryRes = await userAApi.get<dynamic>(
        '/pods/$matchedPodId/messages?before=$nextCursor&limit=1',
      );
      expect((nextHistoryRes.data as List).isNotEmpty, isTrue);

      // Cleanup realtime clients and temp directory
      await subA.cancel();
      await subB.cancel();
      clientA.dispose();
      clientB.dispose();
      await tempDir.delete(recursive: true);

      // 6. User A leaves pod via POST /pods/{id}/leave
      final leaveRes = await userAApi.post<Map<String, dynamic>>('/pods/$matchedPodId/leave');
      expect(leaveRes.data['message'], 'left pod successfully');

      // User A no longer has active pods
      final userAPods = await userAApi.get<dynamic>('/pods');
      expect((userAPods.data as List).isEmpty, isTrue);

      // 6. User B blocks User A via POST /blocks
      final blockRes = await userBApi.post<Map<String, dynamic>>(
        '/blocks',
        data: {'blocked_user_id': userAId},
      );
      expect(blockRes.data['blocked_user_id'], userAId);
      expect(blockRes.data['user_id'], userBId);
    });
  });
}
