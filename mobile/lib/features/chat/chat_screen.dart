import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/realtime_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';
import 'chat_provider.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/typing_indicator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? podId;

  const ChatScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _resolvedPodId;
  RealtimeClient? _realtimeClient;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initChatSession();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // In a reversed list, reaching maxScrollExtent means scrolling to the top (oldest messages)
    if (currentScroll >= maxScroll - 150) {
      if (_resolvedPodId != null && _resolvedPodId!.isNotEmpty) {
        final apiClient = ref.read(apiClientProvider);
        ref.read(chatProvider(_resolvedPodId!).notifier).fetchOlderMessages(apiClient);
      }
    }
  }

  Future<void> _initChatSession() async {
    final activePod = ref.read(activePodDetailProvider).pod;
    final podId = widget.podId ??
        ref.read(currentPodIdProvider) ??
        activePod?.id ??
        '';

    if (podId.isEmpty) return;
    _resolvedPodId = podId;

    final apiClient = ref.read(apiClientProvider);
    final realtimeClient = ref.read(realtimeClientProvider);
    _realtimeClient = realtimeClient;
    final currentUser = ref.read(currentUserProvider);
    final currentUserId = currentUser?.id ?? '';

    // 1. Initialize chat notifier realtime event listener
    final chatNotifier = ref.read(chatProvider(podId).notifier);
    chatNotifier.initRealtime(
      realtimeClient: realtimeClient,
      apiClient: apiClient,
      currentUserId: currentUserId,
    );

    // 2. Fetch message history
    await chatNotifier.fetchHistory(apiClient);

    // 3. Connect WebSocket for this pod in background
    unawaited(realtimeClient.connect(podId));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();

    // Close the socket when leaving the chat screen
    if (_resolvedPodId != null) {
      _realtimeClient?.disconnect();
    }
    super.dispose();
  }

  Future<void> _handlePickAndUploadImage() async {
    if (_resolvedPodId == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (picked == null) return;

      final file = File(picked.path);
      final apiClient = ref.read(apiClientProvider);

      await ref
          .read(chatProvider(_resolvedPodId!).notifier)
          .uploadAttachment(apiClient: apiClient, file: file);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to pick photo.')),
        );
      }
    }
  }

  Future<void> _handleSendMessage() async {
    if (_resolvedPodId == null) return;

    final text = _textController.text.trim();
    final chatNotifier = ref.read(chatProvider(_resolvedPodId!).notifier);
    final chatState = ref.read(chatProvider(_resolvedPodId!));

    if (text.isEmpty && chatState.pendingAttachmentUrl == null) {
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    _textController.clear();

    final ok = await chatNotifier.sendMessage(
      apiClient: apiClient,
      text: text.isNotEmpty ? text : null,
    );

    if (ok && _scrollController.hasClients) {
      // Animate to bottom (0 in reversed list)
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?.id ?? '';
    final activePod = ref.watch(activePodDetailProvider).pod;

    final podId = _resolvedPodId ??
        widget.podId ??
        ref.watch(currentPodIdProvider) ??
        activePod?.id ??
        '';

    final partner = activePod?.partner(currentUserId);
    final partnerName = partner?.user.name ?? 'Partner';

    final chatState = ref.watch(chatProvider(podId));
    final chatNotifier = ref.read(chatProvider(podId).notifier);
    final realtimeStatus = ref.watch(
      realtimeClientProvider.select((c) => c.currentStatus),
    );

    final canSend = !chatState.isSending &&
        (_textController.text.trim().isNotEmpty ||
            chatState.pendingAttachmentUrl != null);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Text(
                partnerName.isNotEmpty
                    ? partnerName.substring(0, 1).toUpperCase()
                    : 'P',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    partnerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: realtimeStatus == RealtimeConnectionStatus.connected
                              ? theme.colorScheme.primary
                              : (realtimeStatus == RealtimeConnectionStatus.reconnecting
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        realtimeStatus == RealtimeConnectionStatus.connected
                            ? 'Realtime'
                            : (realtimeStatus == RealtimeConnectionStatus.reconnecting
                                ? 'Reconnecting...'
                                : 'Connecting...'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (chatState.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: ErrorBanner(message: chatState.errorMessage!),
              ),

            // Main Message List
            Expanded(
              child: chatState.isLoadingHistory && chatState.messages.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : chatState.messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 56,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'No Messages Yet',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Say hello to $partnerName and start keeping each other accountable!',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          itemCount: chatState.messages.length +
                              (chatState.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (chatState.isLoadingMore &&
                                index == chatState.messages.length) {
                              return Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              );
                            }

                            // Reversed list: index 0 is the newest message
                            final messageIndex =
                                chatState.messages.length - 1 - index;
                            final msg = chatState.messages[messageIndex];
                            final isMe = msg.senderId == currentUserId;

                            return ChatBubble(
                              message: msg,
                              isMe: isMe,
                              partnerName: partnerName,
                            );
                          },
                        ),
            ),

            // Typing Indicator
            if (chatState.isPartnerTyping)
              TypingIndicator(partnerName: partnerName),

            // Pending Attachment Preview Bar
            if (chatState.pendingAttachmentUrl != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                color: theme.colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.borderRadiusSm,
                      child: Image.network(
                        chatState.pendingAttachmentUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Photo attached for progress proof',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Remove photo',
                      onPressed: chatNotifier.clearPendingAttachment,
                    ),
                  ],
                ),
              ),

            // Uploading progress banner
            if (chatState.isUploadingAttachment)
              LinearProgressIndicator(
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),

            // Bottom Input Bar
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.photo_camera_rounded,
                      color: chatState.isUploadingAttachment
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                    tooltip: 'Attach progress proof',
                    onPressed: chatState.isUploadingAttachment
                        ? null
                        : _handlePickAndUploadImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Message $partnerName...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                      ),
                      onChanged: (text) {
                        setState(() {});
                        if (text.trim().isNotEmpty && _resolvedPodId != null) {
                          final apiClient = ref.read(apiClientProvider);
                          ref
                              .read(chatProvider(_resolvedPodId!).notifier)
                              .notifyTyping(apiClient);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: chatState.isSending
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: canSend
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                    tooltip: 'Send message',
                    onPressed: canSend ? _handleSendMessage : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
