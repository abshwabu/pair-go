import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/realtime_client.dart';
import 'models/chat_message_model.dart';

class ChatState {
  final List<ChatMessageModel> messages;
  final bool isLoadingHistory;
  final bool isLoadingMore;
  final bool isSending;
  final bool isUploadingAttachment;
  final String? pendingAttachmentUrl;
  final String? nextCursor;
  final bool hasMoreHistory;
  final bool isPartnerTyping;
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.isLoadingHistory = false,
    this.isLoadingMore = false,
    this.isSending = false,
    this.isUploadingAttachment = false,
    this.pendingAttachmentUrl,
    this.nextCursor,
    this.hasMoreHistory = false,
    this.isPartnerTyping = false,
    this.errorMessage,
  });

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    bool? isLoadingHistory,
    bool? isLoadingMore,
    bool? isSending,
    bool? isUploadingAttachment,
    String? pendingAttachmentUrl,
    bool clearPendingAttachment = false,
    String? nextCursor,
    bool? hasMoreHistory,
    bool? isPartnerTyping,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSending: isSending ?? this.isSending,
      isUploadingAttachment:
          isUploadingAttachment ?? this.isUploadingAttachment,
      pendingAttachmentUrl: clearPendingAttachment
          ? null
          : (pendingAttachmentUrl ?? this.pendingAttachmentUrl),
      nextCursor: nextCursor ?? this.nextCursor,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      isPartnerTyping: isPartnerTyping ?? this.isPartnerTyping,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  final String podId;

  StreamSubscription<RealtimeEvent>? _eventSubscription;
  Timer? _typingTimeoutTimer;
  DateTime? _lastTypingSentTime;

  ChatNotifier(this.podId);

  @override
  ChatState build() {
    ref.onDispose(() {
      _eventSubscription?.cancel();
      _typingTimeoutTimer?.cancel();
    });
    return const ChatState();
  }

  /// Initializes realtime listener for the chat session.
  void initRealtime({
    required RealtimeClient realtimeClient,
    required ApiClient apiClient,
    required String currentUserId,
  }) {
    _eventSubscription?.cancel();

    _eventSubscription = realtimeClient.events.listen((event) {
      if (event.podId != podId) return;

      switch (event.type) {
        case RealtimeEventType.message:
          try {
            final incoming = ChatMessageModel.fromJson(event.data);
            _appendMessage(incoming);

            // If message is from partner, clear partner typing indicator
            if (incoming.senderId != currentUserId) {
              _typingTimeoutTimer?.cancel();
              state = state.copyWith(isPartnerTyping: false);
            }
          } catch (_) {}
          break;

        case RealtimeEventType.typing:
          final senderUserId = event.data['user_id'] as String? ?? '';
          if (senderUserId.isNotEmpty && senderUserId != currentUserId) {
            _onPartnerTyping();
          }
          break;

        case RealtimeEventType.reconnect:
          // Gap fill: fetch latest messages after reconnect
          fetchLatestGap(apiClient);
          break;

        default:
          break;
      }
    });
  }

  void _onPartnerTyping() {
    _typingTimeoutTimer?.cancel();
    state = state.copyWith(isPartnerTyping: true);

    // Hide indicator 4 seconds after last typing event
    _typingTimeoutTimer = Timer(const Duration(seconds: 4), () {
      state = state.copyWith(isPartnerTyping: false);
    });
  }

  void _appendMessage(ChatMessageModel newMsg) {
    // Deduplicate by message ID
    if (state.messages.any((m) => m.id == newMsg.id)) {
      return;
    }

    final updated = List<ChatMessageModel>.from(state.messages)..add(newMsg);
    // Sort oldest-to-newest by createdAt
    updated.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    state = state.copyWith(messages: updated);
  }

  /// Initial load of message history.
  Future<void> fetchHistory(ApiClient apiClient) async {
    if (podId.isEmpty) return;

    state = state.copyWith(isLoadingHistory: true, clearErrorMessage: true);

    try {
      final res = await apiClient.get<dynamic>('/pods/$podId/messages?limit=50');
      final data = res.data;
      final meta = res.meta;

      final items = <ChatMessageModel>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            items.add(ChatMessageModel.fromJson(item));
          } else if (item is Map) {
            items.add(ChatMessageModel.fromJson(item.cast<String, dynamic>()));
          }
        }
      }

      // Sort oldest to newest
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final nextCursor = meta?['next_cursor'] as String?;

      state = state.copyWith(
        messages: items,
        isLoadingHistory: false,
        nextCursor: nextCursor,
        hasMoreHistory: nextCursor != null && nextCursor.isNotEmpty,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoadingHistory: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoadingHistory: false,
        errorMessage: 'Failed to load messages.',
      );
    }
  }

  /// Loads older messages using next_cursor when scrolled to the top.
  Future<void> fetchOlderMessages(ApiClient apiClient) async {
    if (podId.isEmpty ||
        state.isLoadingMore ||
        !state.hasMoreHistory ||
        state.nextCursor == null) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);

    try {
      final cursor = state.nextCursor!;
      final res = await apiClient.get<dynamic>(
        '/pods/$podId/messages?before=$cursor&limit=50',
      );
      final data = res.data;
      final meta = res.meta;

      final olderItems = <ChatMessageModel>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            olderItems.add(ChatMessageModel.fromJson(item));
          } else if (item is Map) {
            olderItems.add(ChatMessageModel.fromJson(item.cast<String, dynamic>()));
          }
        }
      }

      // Merge and deduplicate
      final existingIds = state.messages.map((m) => m.id).toSet();
      final freshOlder = olderItems.where((m) => !existingIds.contains(m.id)).toList();

      final combined = [...freshOlder, ...state.messages];
      combined.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final nextCursor = meta?['next_cursor'] as String?;

      state = state.copyWith(
        messages: combined,
        isLoadingMore: false,
        nextCursor: nextCursor,
        hasMoreHistory: nextCursor != null && nextCursor.isNotEmpty,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Refetches latest messages to fill gaps after reconnect.
  Future<void> fetchLatestGap(ApiClient apiClient) async {
    if (podId.isEmpty) return;

    try {
      final res = await apiClient.get<dynamic>('/pods/$podId/messages?limit=50');
      final data = res.data;

      if (data is List) {
        final existingIds = state.messages.map((m) => m.id).toSet();
        final newBatch = <ChatMessageModel>[];

        for (final item in data) {
          final map = item is Map<String, dynamic>
              ? item
              : (item is Map ? item.cast<String, dynamic>() : null);
          if (map != null) {
            final msg = ChatMessageModel.fromJson(map);
            if (!existingIds.contains(msg.id)) {
              newBatch.add(msg);
            }
          }
        }

        if (newBatch.isNotEmpty) {
          final updated = [...state.messages, ...newBatch];
          updated.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          state = state.copyWith(messages: updated);
        }
      }
    } catch (_) {
      // Background gap fill error is non-fatal
    }
  }

  /// Sends a typing event at most once per 3 seconds while typing.
  Future<void> notifyTyping(ApiClient apiClient) async {
    final now = DateTime.now();
    if (_lastTypingSentTime != null &&
        now.difference(_lastTypingSentTime!) < const Duration(seconds: 3)) {
      return;
    }
    _lastTypingSentTime = now;

    try {
      await apiClient.post<dynamic>('/pods/$podId/typing');
    } catch (_) {
      // Non-fatal
    }
  }

  /// Uploads progress-proof image to POST /api/v1/pods/{pod}/attachments.
  Future<bool> uploadAttachment({
    required ApiClient apiClient,
    required File file,
  }) async {
    state = state.copyWith(
      isUploadingAttachment: true,
      clearErrorMessage: true,
    );

    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: fileName,
        ),
      });

      final res = await apiClient.post<Map<String, dynamic>>(
        '/pods/$podId/attachments',
        data: formData,
      );

      final url = res.data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const ApiException(message: 'Upload failed: missing attachment URL');
      }

      state = state.copyWith(
        isUploadingAttachment: false,
        pendingAttachmentUrl: url,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isUploadingAttachment: false,
        errorMessage: e.message,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isUploadingAttachment: false,
        errorMessage: 'Failed to upload photo attachment.',
      );
      return false;
    }
  }

  void clearPendingAttachment() {
    state = state.copyWith(clearPendingAttachment: true);
  }

  /// Sends a chat message.
  Future<bool> sendMessage({
    required ApiClient apiClient,
    String? text,
  }) async {
    final body = text?.trim();
    final attachmentUrl = state.pendingAttachmentUrl;

    if ((body == null || body.isEmpty) &&
        (attachmentUrl == null || attachmentUrl.isEmpty)) {
      return false;
    }

    state = state.copyWith(isSending: true, clearErrorMessage: true);

    try {
      final payload = <String, dynamic>{
        if (body != null && body.isNotEmpty) 'body': body,
        if (attachmentUrl != null && attachmentUrl.isNotEmpty)
          'attachment_url': attachmentUrl,
      };

      final res = await apiClient.post<Map<String, dynamic>>(
        '/pods/$podId/messages',
        data: payload,
      );

      final sentMessage = ChatMessageModel.fromJson(res.data);
      _appendMessage(sentMessage);

      state = state.copyWith(
        isSending: false,
        clearPendingAttachment: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: e.message,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSending: false,
        errorMessage: 'Failed to send message.',
      );
      return false;
    }
  }
}

/// Riverpod FamilyNotifier per pod managing message history, sending, typing, and realtime stream sync.
final chatProvider =
    NotifierProvider.family<ChatNotifier, ChatState, String>(
  (podId) => ChatNotifier(podId),
);
