import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';
import 'models/streak_model.dart';
import 'streak_provider.dart';
import 'widgets/checkin_modal.dart';

/// Screen displaying current streak, best streak, today's member check-in progress,
/// broken streak recovery prompt (if broken), and historical daily participation.
class StreakDetailScreen extends ConsumerStatefulWidget {
  final String? podId;

  const StreakDetailScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<StreakDetailScreen> createState() => _StreakDetailScreenState();
}

class _StreakDetailScreenState extends ConsumerState<StreakDetailScreen> {
  String? _resolvedPodId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final activePod = ref.read(activePodDetailProvider).pod;
    final id = widget.podId ??
        ref.read(currentPodIdProvider) ??
        activePod?.id ??
        '';

    if (id.isEmpty) return;
    _resolvedPodId = id;

    final apiClient = ref.read(apiClientProvider);
    final notifier = ref.read(podStreakProvider(id).notifier);
    await Future.wait([
      notifier.fetchStreak(apiClient, forceRefresh: true),
      notifier.fetchHistory(apiClient),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final activePod = ref.watch(activePodDetailProvider).pod;

    final podId = _resolvedPodId ??
        widget.podId ??
        ref.watch(currentPodIdProvider) ??
        activePod?.id ??
        '';

    final partner = activePod?.partner(currentUser?.id);
    final partnerName = partner?.user.name ?? 'Partner';

    final streakState = ref.watch(podStreakProvider(podId));
    final streak = streakState.streak;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Streak & Check-ins'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (streakState.errorMessage != null && streak == null) ...[
                ErrorBanner(message: streakState.errorMessage!),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _loadData,
                  child: const Text('Retry'),
                ),
              ],

              // Broken Streak Recovery Prompt Card (if current == 0 and best > 0)
              if (streak != null && streak.isStreakBroken) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
                    borderRadius: AppRadius.borderRadiusLg,
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: theme.colorScheme.error,
                            size: 24,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Streak Paused',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Your streak was broken, but your record of ${streak.bestStreak} days remains intact! Start a fresh streak together today.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.tonal(
                        onPressed: () {
                          context.push(
                            AppRoutes.streakRecoveryPath,
                            extra: podId,
                          );
                        },
                        child: const Text('View Recovery Options & Nudge'),
                      ),
                    ],
                  ),
                ),
              ],

              // 1. Streak Stat Summary Cards
              Row(
                children: [
                  Expanded(
                    child: Card(
                      elevation: 0,
                      color: theme.colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.borderRadiusLg,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            Icon(
                              Icons.local_fire_department_rounded,
                              size: 36,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '${streak?.currentStreak ?? 0}',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              'Current Streak',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.borderRadiusLg,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              size: 36,
                              color: theme.colorScheme.tertiary,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '${streak?.bestStreak ?? 0}',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'Best Streak',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // 2. Today's Pod Check-in Status Card
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusLg,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today\'s Accountability',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Streaks increase when both members complete their daily check-in (UTC).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _buildMemberStatusTile(
                        context,
                        title: 'You',
                        isCheckedIn: streak?.meCheckedInToday ?? false,
                        theme: theme,
                      ),
                      const Divider(height: AppSpacing.md),
                      _buildMemberStatusTile(
                        context,
                        title: partnerName,
                        isCheckedIn: streak?.partnerCheckedInToday ?? false,
                        theme: theme,
                      ),
                      if (streak != null && !streak.meCheckedInToday) ...[
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Check In Now'),
                            onPressed: () {
                              CheckInModal.show(
                                context,
                                podId: podId,
                                partnerName: partnerName,
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // 3. History List Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Check-in History',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (streakState.isLoadingHistory)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // History Items
              if (streakState.history.isEmpty && !streakState.isLoadingHistory)
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'No check-ins recorded yet.\nCheck in today to start your streak!',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: streakState.history.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = streakState.history[index];
                    return _buildHistoryItemTile(context, item, theme);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberStatusTile(
    BuildContext context, {
    required String title,
    required bool isCheckedIn,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        Icon(
          isCheckedIn
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: isCheckedIn
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          size: 22,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: isCheckedIn
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Text(
            isCheckedIn ? 'Checked in' : 'Pending',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isCheckedIn
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryItemTile(
    BuildContext context,
    DailyCheckInItem item,
    ThemeData theme,
  ) {
    final bothCompleted = item.bothCheckedIn;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bothCompleted
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(
          color: bothCompleted
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            bothCompleted
                ? Icons.local_fire_department_rounded
                : Icons.person_outline_rounded,
            color: bothCompleted
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.date,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  bothCompleted
                      ? 'Both members completed check-in'
                      : '1 member completed check-in',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: bothCompleted
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHigh,
              borderRadius: AppRadius.borderRadiusSm,
            ),
            child: Text(
              bothCompleted ? 'Both Completed' : '1 of 2',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: bothCompleted
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
