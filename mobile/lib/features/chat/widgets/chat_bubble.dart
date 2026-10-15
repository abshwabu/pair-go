import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_message_model.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final String? partnerName;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.partnerName,
  });

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bubbleBg = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMe
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final timeColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.75)
        : theme.colorScheme.onSurfaceVariant;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.lg),
      topRight: const Radius.circular(AppRadius.lg),
      bottomLeft: Radius.circular(isMe ? AppRadius.lg : AppSpacing.xs),
      bottomRight: Radius.circular(isMe ? AppSpacing.xs : AppRadius.lg),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bubbleBg,
            borderRadius: borderRadius,
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Partner name label on incoming messages
              if (!isMe && partnerName != null && partnerName!.isNotEmpty) ...[
                Text(
                  partnerName!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
              ],

              // Photo attachment if present
              if (message.hasAttachment) ...[
                ClipRRect(
                  borderRadius: AppRadius.borderRadiusMd,
                  child: Image.network(
                    message.attachmentUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 160,
                        color: theme.colorScheme.surface,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 100,
                        color: theme.colorScheme.surface,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Failed to load image',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (message.hasBody) const SizedBox(height: AppSpacing.xs),
              ],

              // Text body if present
              if (message.hasBody) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    message.body!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 2),

              // Timestamp
              Text(
                _formatTime(message.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: timeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
