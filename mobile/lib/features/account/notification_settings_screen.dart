import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import 'in_app_notifications_provider.dart';
import 'models/in_app_notification_model.dart';
import 'notification_preferences_provider.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiClient = ref.read(apiClientProvider);
      ref.read(inAppNotificationsProvider.notifier).loadNotifications(apiClient);
    });
  }

  void _handleNotificationTap(InAppNotification notif) {
    final apiClient = ref.read(apiClientProvider);

    // Mark as read if not already read
    if (!notif.isRead) {
      ref.read(inAppNotificationsProvider.notifier).markAsRead(apiClient, notif.id);
    }

    final podId = notif.podId;

    switch (notif.type) {
      case 'new_message':
        if (podId != null && podId.isNotEmpty) {
          context.push(AppRoutes.chatPath, extra: podId);
        } else {
          context.push(AppRoutes.podHomePath);
        }
        break;
      case 'checkin_nudge':
        if (podId != null && podId.isNotEmpty) {
          context.push(AppRoutes.checkinPath, extra: podId);
        } else {
          context.push(AppRoutes.podHomePath);
        }
        break;
      case 'streak_broken':
        if (podId != null && podId.isNotEmpty) {
          context.push(AppRoutes.streakDetailPath, extra: podId);
        } else {
          context.push(AppRoutes.podHomePath);
        }
        break;
      case 'match_proposed':
        context.push(AppRoutes.matchProposalPath);
        break;
      case 'match_confirmed':
        context.push(AppRoutes.matchConfirmedPath, extra: podId);
        break;
      case 'match_declined':
        context.push(AppRoutes.findingMatchPath);
        break;
      case 'match_found':
        context.push(AppRoutes.matchConfirmedPath, extra: podId);
        break;
      default:
        if (podId != null && podId.isNotEmpty) {
          context.push(AppRoutes.podHomePath, extra: podId);
        }
        break;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'new_message':
        return Icons.chat_bubble_outline_rounded;
      case 'checkin_nudge':
        return Icons.touch_app_outlined;
      case 'streak_broken':
        return Icons.warning_amber_rounded;
      case 'match_proposed':
        return Icons.person_search_rounded;
      case 'match_confirmed':
        return Icons.celebration_rounded;
      case 'match_declined':
        return Icons.sync_rounded;
      case 'match_found':
        return Icons.people_outline_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = ref.watch(notificationPreferencesProvider);
    final prefsNotifier = ref.read(notificationPreferencesProvider.notifier);
    final notifsState = ref.watch(inAppNotificationsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          children: [
            // Preference Toggles Section
            Text(
              'PUSH NOTIFICATION PREFERENCES',
              style: AppTypography.labelMedium.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Select which notifications trigger local alerts on your device.',
              style: AppTypography.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusCard,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    value: prefs.newMessage,
                    onChanged: prefsNotifier.toggleNewMessage,
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Chat Messages',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Alerts when your partner sends a message',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  SwitchListTile(
                    value: prefs.checkinNudge,
                    onChanged: prefsNotifier.toggleCheckinNudge,
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Icon(
                        Icons.touch_app_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Check-in Nudges',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Reminders when your partner nudges you',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  SwitchListTile(
                    value: prefs.streakBroken,
                    onChanged: prefsNotifier.toggleStreakBroken,
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Streak Alerts',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Warnings when a streak is in jeopardy or broken',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  SwitchListTile(
                    value: prefs.matchProposed,
                    onChanged: prefsNotifier.toggleMatchProposed,
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Icon(
                        Icons.person_search_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Match Proposals',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Alerts when a new partner proposal is ready',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  SwitchListTile(
                    value: prefs.matchConfirmed,
                    onChanged: prefsNotifier.toggleMatchConfirmed,
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Icon(
                        Icons.celebration_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Match Confirmed',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Alerts when both partners accept a match',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  SwitchListTile(
                    value: prefs.matchDeclined,
                    onChanged: prefsNotifier.toggleMatchDeclined,
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Icon(
                        Icons.sync_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Match Updates',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Alerts when searching resumes after a declined match',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // In-app Notifications List Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'IN-APP NOTIFICATIONS',
                  style: AppTypography.labelMedium.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                if (notifsState.isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: () {
                      final apiClient = ref.read(apiClientProvider);
                      ref
                          .read(inAppNotificationsProvider.notifier)
                          .loadNotifications(apiClient);
                    },
                    tooltip: 'Refresh',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            if (notifsState.errorMessage != null) ...[
              ErrorBanner(message: notifsState.errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],

            if (!notifsState.isLoading && notifsState.notifications.isEmpty)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusCard,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: EmptyState(
                  icon: Icons.notifications_off_outlined,
                  title: 'No Notifications Yet',
                  message: 'Your updates and alerts will appear here.',
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusCard,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: notifsState.notifications.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final notif = notifsState.notifications[index];
                    final isRead = notif.isRead;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isRead
                              ? theme.colorScheme.surfaceContainerHigh
                              : theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _iconForType(notif.type),
                          color: isRead
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              notif.title,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight:
                                    isRead ? FontWeight.normal : FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (notif.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              notif.body,
                              style: AppTypography.bodySmall.copyWith(
                                color: isRead
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            _formatTimestamp(notif.createdAt),
                            style: AppTypography.labelSmall.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      onTap: () => _handleNotificationTap(notif),
                    );
                  },
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
