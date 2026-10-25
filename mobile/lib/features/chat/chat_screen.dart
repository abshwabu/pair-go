import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/realtime_client.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_shimmer.dart';
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
  bool _showScrollToBottom = false;

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

    if (currentScroll > 300 && !_showScrollToBottom) {
      setState(() {
        _showScrollToBottom = true;
      });
    } else if (currentScroll <= 300 && _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = false;
      });
    }

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

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
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
            AppAvatar(
              imageUrl: partner?.user.avatarUrl,
              name: partnerName,
              size: AppAvatarSize.sm,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    partnerName,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
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
                              ? tokens.success
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
                        style: AppTypography.labelSmall.copyWith(
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
        child: Stack(
          children: [
            Column(
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
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppShimmer.card(height: 52),
                              const SizedBox(height: AppSpacing.sm),
                              Align(
                                alignment: Alignment.centerRight,
                                child: AppShimmer.card(height: 44),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              AppShimmer.card(height: 60),
                            ],
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
                                      style: AppTypography.titleMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      'Say hello to $partnerName and start keeping each other accountable!',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.bodyMedium.copyWith(
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

                                // Consecutive check with preceding message (messageIndex - 1)
                                bool isConsecutive = false;
                                if (messageIndex > 0) {
                                  final prevMsg = chatState.messages[messageIndex - 1];
                                  if (prevMsg.senderId == msg.senderId &&
                                      msg.createdAt.difference(prevMsg.createdAt).inMinutes < 3) {
                                    isConsecutive = true;
                                  }
                                }

                                // Day separator check with next older message (messageIndex - 1)
                                bool showDateHeader = false;
                                if (messageIndex == 0) {
                                  showDateHeader = true;
                                } else {
                                  final olderMsg = chatState.messages[messageIndex - 1];
                                  if (_isDifferentDay(msg.createdAt, olderMsg.createdAt)) {
                                    showDateHeader = true;
                                  }
                                }

                                final bubble = ChatBubble(
                                  message: msg,
                                  isMe: isMe,
                                  partnerName: partnerName,
                                  isConsecutive: isConsecutive,
                                );

                                if (showDateHeader) {
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppSpacing.sm,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.sm,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceContainerHighest,
                                            borderRadius: AppRadius.borderRadiusFull,
                                          ),
                                          child: Text(
                                            _formatDateSeparator(msg.createdAt),
                                            style: AppTypography.labelSmall.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                      bubble,
                                    ],
                                  );
                                }

                                return bubble;
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
                            style: AppTypography.bodySmall.copyWith(
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

                // Bottom Floating Pill Composer
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.borderRadiusFull,
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
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
                            style: AppTypography.bodyMedium.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Message $partnerName...',
                              hintStyle: AppTypography.bodyMedium.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
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
                                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                          tooltip: 'Send message',
                          onPressed: canSend ? _handleSendMessage : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // "Scroll to latest" button when scrolled up
            if (_showScrollToBottom)
              Positioned(
                bottom: 72,
                right: 16,
                child: FloatingActionButton.small(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.primary,
                  elevation: 4,
                  onPressed: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: const Icon(Icons.arrow_downward_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
