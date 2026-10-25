import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import 'blocked_users_provider.dart';
import 'models/blocked_user_model.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  String? _unblockingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiClient = ref.read(apiClientProvider);
      ref.read(blockedUsersProvider.notifier).loadBlocks(apiClient);
    });
  }

  Future<void> _handleUnblock(BlockedUserModel block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusCard,
        ),
        title: Text('Unblock ${block.name}?'),
        content: Text(
          'Are you sure you want to unblock ${block.name}? They will be removed from your blocked list and may be matched with you in future pods.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _unblockingId = block.id;
    });

    final apiClient = ref.read(apiClientProvider);
    final success =
        await ref.read(blockedUsersProvider.notifier).unblock(apiClient, block.id);

    if (mounted) {
      setState(() {
        _unblockingId = null;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${block.name} has been unblocked.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Blocked Users',
          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            final apiClient = ref.read(apiClientProvider);
            await ref.read(blockedUsersProvider.notifier).loadBlocks(apiClient);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            children: [
              if (state.errorMessage != null) ...[
                ErrorBanner(message: state.errorMessage!),
                const SizedBox(height: AppSpacing.md),
              ],

              if (state.isLoading && state.blocks.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                )
              else if (state.blocks.isEmpty)
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
                    icon: Icons.block_outlined,
                    title: 'No Blocked Users',
                    message:
                        'Users you block will appear here. You can unblock them at any time.',
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
                    itemCount: state.blocks.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final block = state.blocks[index];
                      final isUnblocking = _unblockingId == block.id;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        leading: AppAvatar(
                          name: block.name,
                          imageUrl: block.avatarUrl,
                          size: AppAvatarSize.md,
                        ),
                        title: Text(
                          block.name,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        subtitle: block.createdAt != null
                            ? Text(
                                'Blocked on ${block.createdAt!.year}-${block.createdAt!.month.toString().padLeft(2, '0')}-${block.createdAt!.day.toString().padLeft(2, '0')}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        trailing: isUnblocking
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: AppRadius.borderRadiusLg,
                                  ),
                                ),
                                onPressed: () => _handleUnblock(block),
                                child: const Text('Unblock'),
                              ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
