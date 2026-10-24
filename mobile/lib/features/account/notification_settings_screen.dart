import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
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
      case 'match_found':
        if (podId != null && podId.isNotEmpty) {
          context.push(AppRoutes.podHomePath, extra: podId);
        } else {
          context.push(AppRoutes.podHomePath);
        }
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
        title: const Text('Notifications'),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Preference Toggles Section
            Text(
              'PUSH NOTIFICATION PREFERENCES',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Select which notifications trigger local alerts on your device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.borderRadiusMd,
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    value: prefs.newMessage,
                    onChanged: prefsNotifier.toggleNewMessage,
                    secondary: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Chat Messages'),
                    subtitle: const Text('Alerts when your partner sends a message'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: prefs.checkinNudge,
                    onChanged: prefsNotifier.toggleCheckinNudge,
                    secondary: Icon(
                      Icons.touch_app_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Check-in Nudges'),
                    subtitle: const Text('Reminders when your partner nudges you'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: prefs.streakBroken,
                    onChanged: prefsNotifier.toggleStreakBroken,
                    secondary: Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Streak Alerts'),
                    subtitle: const Text('Warnings when a streak is in jeopardy or broken'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: prefs.matchFound,
                    onChanged: prefsNotifier.toggleMatchFound,
                    secondary: Icon(
                      Icons.people_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Match Found'),
                    subtitle: const Text('Notifications when you are paired in a new pod'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // In-app Notifications List Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'IN-APP NOTIFICATIONS',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                if (notifsState.isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
            const SizedBox(height: AppSpacing.sm),

            if (notifsState.errorMessage != null) ...[
              ErrorBanner(message: notifsState.errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],

            if (!notifsState.isLoading && notifsState.notifications.isEmpty)
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusMd,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'No Notifications Yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Your updates and alerts will appear here.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusMd,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: notifsState.notifications.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notif = notifsState.notifications[index];
                    final isRead = notif.isRead;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isRead
                            ? theme.colorScheme.surfaceContainer
                            : theme.colorScheme.primaryContainer,
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
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight:
                                    isRead ? FontWeight.normal : FontWeight.bold,
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isRead
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            _formatTimestamp(notif.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                      ),
                      onTap: () => _handleNotificationTap(notif),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
