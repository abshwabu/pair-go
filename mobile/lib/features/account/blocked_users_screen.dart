import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
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
        title: const Text('Blocked Users'),
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            final apiClient = ref.read(apiClientProvider);
            await ref.read(blockedUsersProvider.notifier).loadBlocks(apiClient);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (state.errorMessage != null) ...[
                ErrorBanner(message: state.errorMessage!),
                const SizedBox(height: AppSpacing.md),
              ],

              if (state.isLoading && state.blocks.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (state.blocks.isEmpty)
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
                            Icons.block_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'No Blocked Users',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Users you block will appear here. You can unblock them at any time.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
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
                    itemCount: state.blocks.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final block = state.blocks[index];
                      final isUnblocking = _unblockingId == block.id;

                      ImageProvider? avatarImage;
                      if (block.avatarUrl != null && block.avatarUrl!.isNotEmpty) {
                        avatarImage = NetworkImage(block.avatarUrl!);
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? Icon(
                                  Icons.person_rounded,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                        ),
                        title: Text(
                          block.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: block.createdAt != null
                            ? Text(
                                'Blocked on ${block.createdAt!.year}-${block.createdAt!.month.toString().padLeft(2, '0')}-${block.createdAt!.day.toString().padLeft(2, '0')}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        trailing: isUnblocking
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs,
                                  ),
                                ),
                                onPressed: () => _handleUnblock(block),
                                child: const Text('Unblock'),
                              ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
