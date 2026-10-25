import 'package:flutter/material.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../core/theme/app_typography.dart';
import '../models/chat_message_model.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final String? partnerName;
  final bool isConsecutive;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.partnerName,
    this.isConsecutive = false,
  });

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showImagePreview(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color.fromARGB(0, 0, 0, 0),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: AppRadius.borderRadiusCard,
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surface.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    final bubbleBg = isMe ? tokens.bubbleSelf : tokens.bubblePartner;
    final textColor = isMe
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final timeColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.75)
        : theme.colorScheme.onSurfaceVariant;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.card),
      topRight: const Radius.circular(AppRadius.card),
      bottomLeft: Radius.circular(isMe ? AppRadius.card : AppSpacing.xs),
      bottomRight: Radius.circular(isMe ? AppSpacing.xs : AppRadius.card),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: isConsecutive ? 2 : AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bubbleBg,
            borderRadius: borderRadius,
            border: isMe
                ? null
                : Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1.0,
                  ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Partner name label on incoming messages
              if (!isMe && !isConsecutive && partnerName != null && partnerName!.isNotEmpty) ...[
                Text(
                  partnerName!,
                  style: AppTypography.labelSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
              ],

              // Photo attachment if present
              if (message.hasAttachment) ...[
                GestureDetector(
                  onTap: () => _showImagePreview(context, message.attachmentUrl!),
                  child: ClipRRect(
                    borderRadius: AppRadius.borderRadiusMd,
                    child: Image.network(
                      message.attachmentUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 160,
                          color: theme.colorScheme.surfaceContainerHighest,
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
                          color: theme.colorScheme.surfaceContainerHighest,
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
                                style: AppTypography.bodySmall.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (message.hasBody) const SizedBox(height: AppSpacing.xs),
              ],

              // Text body if present
              if (message.hasBody) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Text(
                    message.body!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: textColor,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 2),

              // Timestamp
              Text(
                _formatTime(message.createdAt),
                style: AppTypography.labelSmall.copyWith(
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
