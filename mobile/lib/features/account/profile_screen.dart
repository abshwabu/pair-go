import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/network/fcm_service.dart';
import '../../core/router.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_state.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const Map<String, String> _languages = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'am': 'Amharic',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ar': 'Arabic',
  };

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of Pair?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final apiClient = ref.read(apiClientProvider);
    final tokenStorage = ref.read(tokenStorageProvider);
    final fcmService = ref.read(fcmServiceProvider);

    await fcmService.logout(
      apiClient: apiClient,
      tokenStorage: tokenStorage,
      ref: ref,
    );

    if (context.mounted) {
      context.go(AppRoutes.loginPath);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    final name = user?.name.isNotEmpty == true ? user!.name : 'User';
    final email = user?.email ?? '';
    final timezone = user?.timezone ?? 'UTC';
    final languageCode = user?.language ?? 'en';
    final languageName = _languages[languageCode] ?? languageCode.toUpperCase();
    final avatarUrl = user?.avatarUrl;

    ImageProvider? avatarImage;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarImage = NetworkImage(avatarUrl);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Profile'),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Avatar and Header Card
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Icon(
                            Icons.person_rounded,
                            size: 56,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    name,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () {
                      context.push(
                        AppRoutes.profileSetupPath,
                        extra: {'is_editing': true},
                      );
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit Profile'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Profile Details Section
            Text(
              'ACCOUNT DETAILS',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
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
                  ListTile(
                    leading: Icon(
                      Icons.schedule_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Timezone'),
                    subtitle: Text(timezone),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.language_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Language'),
                    subtitle: Text(languageName),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Settings & Preferences Section
            Text(
              'SETTINGS & PREFERENCES',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
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
                  ListTile(
                    leading: Icon(
                      Icons.notifications_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Notification Settings'),
                    subtitle: const Text('Manage alerts & view notifications'),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () {
                      context.push(AppRoutes.notificationSettingsPath);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.block_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Blocked Users'),
                    subtitle: const Text('Manage users you have blocked'),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () {
                      context.push(AppRoutes.blockedUsersPath);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.lock_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Account Settings'),
                    subtitle: const Text('Password & account termination'),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () {
                      context.push(AppRoutes.accountSettingsPath);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Log Out Button
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => _handleLogout(context, ref),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
