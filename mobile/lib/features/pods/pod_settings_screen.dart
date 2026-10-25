import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/error_banner.dart';
import '../auth/auth_state.dart';
import 'pod_state.dart';

class PodSettingsScreen extends ConsumerStatefulWidget {
  final String? podId;

  const PodSettingsScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<PodSettingsScreen> createState() => _PodSettingsScreenState();
}

class _PodSettingsScreenState extends ConsumerState<PodSettingsScreen> {
  bool _notificationsEnabled = true;
  bool _isPerformingAction = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiClient = ref.read(apiClientProvider);
      ref.read(activePodDetailProvider.notifier).loadPod(
            apiClient: apiClient,
            podId: widget.podId,
          );
    });
  }

  Future<void> _handleLeavePod(String podId, String partnerName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusCard,
          ),
          title: const Text('Leave Pod?'),
          content: Text(
            'Are you sure you want to leave this pod? You will be unpaired from $partnerName and can select a new goal.',
            style: AppTypography.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Leave Pod'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isPerformingAction = true;
      _errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post<Map<String, dynamic>>('/pods/$podId/leave');

      ref.read(activePodDetailProvider.notifier).clearPod();

      if (mounted) {
        context.go(AppRoutes.goalCategoryPath);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
          _errorMessage = 'Failed to leave pod. Please try again.';
        });
      }
    }
  }

  Future<void> _handleBlockPartner(
    String? partnerId,
    String partnerName,
  ) async {
    if (partnerId == null || partnerId.isEmpty) {
      setState(() {
        _errorMessage = 'Partner information not available to block.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusCard,
          ),
          title: const Text('Block Partner?'),
          content: Text(
            'Are you sure you want to block $partnerName? You will immediately leave this pod and will never be paired with them again.',
            style: AppTypography.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Block'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isPerformingAction = true;
      _errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post<Map<String, dynamic>>(
        '/blocks',
        data: {'blocked_user_id': partnerId},
      );

      ref.read(activePodDetailProvider.notifier).clearPod();

      if (mounted) {
        context.go(AppRoutes.goalCategoryPath);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
          _errorMessage = 'Failed to block partner. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podState = ref.watch(activePodDetailProvider);
    final currentUser = ref.watch(currentUserProvider);

    final pod = podState.pod;
    final partner = pod?.partner(currentUser?.id);
    final resolvedPodId = pod?.id ?? widget.podId ?? '';
    final partnerName = partner?.user.name ?? 'Partner';
    final partnerId = partner?.user.id;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pod Settings'),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (_errorMessage != null) ...[
              ErrorBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.lg),
            ],

            if (_isPerformingAction)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),

            // Notifications Section
            Text(
              'NOTIFICATIONS',
              style: AppTypography.labelMedium.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
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
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                value: _notificationsEnabled,
                onChanged: _isPerformingAction
                    ? null
                    : (val) {
                        setState(() {
                          _notificationsEnabled = val;
                        });
                      },
                title: Text(
                  'Push Notifications',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Receive updates for check-ins, todos, and chat messages',
                  style: AppTypography.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Safety & Accountability Section
            Text(
              'SAFETY & ACCOUNTABILITY',
              style: AppTypography.labelMedium.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
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
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.flag_outlined,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Report Partner',
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    subtitle: Text(
                      'Report inappropriate behavior or safety concerns',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                    ),
                    onTap: _isPerformingAction
                        ? null
                        : () {
                            context.go(
                              AppRoutes.reportFormPath,
                              extra: {
                                'reported_user_id': partnerId,
                                'pod_id': resolvedPodId,
                              },
                            );
                          },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.block_rounded,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Block Partner',
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    subtitle: Text(
                      'Block $partnerName and leave this pod immediately',
                      style: AppTypography.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                    ),
                    onTap: _isPerformingAction
                        ? null
                        : () => _handleBlockPartner(partnerId, partnerName),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Pod Membership Section
            Text(
              'POD MEMBERSHIP',
              style: AppTypography.labelMedium.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
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
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.exit_to_app_rounded,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Leave Pod',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                subtitle: Text(
                  'Unpair and return to goal selection to find a new match',
                  style: AppTypography.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                ),
                onTap: _isPerformingAction
                    ? null
                    : () => _handleLeavePod(resolvedPodId, partnerName),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
