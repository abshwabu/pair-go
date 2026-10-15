import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';
import 'streak_provider.dart';
import 'widgets/checkin_modal.dart';

/// Screen displayed when a streak is broken (current_streak == 0 and best_streak > 0).
/// Provides encouraging copy and a "Nudge your partner" button that handles rate limits gracefully.
class StreakRecoveryScreen extends ConsumerStatefulWidget {
  final String? podId;

  const StreakRecoveryScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<StreakRecoveryScreen> createState() => _StreakRecoveryScreenState();
}

class _StreakRecoveryScreenState extends ConsumerState<StreakRecoveryScreen> {
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
    await ref.read(podStreakProvider(id).notifier).fetchStreak(apiClient);
  }

  Future<void> _handleNudge() async {
    if (_resolvedPodId == null) return;
    final apiClient = ref.read(apiClientProvider);
    await ref.read(podStreakProvider(_resolvedPodId!).notifier).nudgePartner(apiClient);
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

    if (streakState.isLoading && streak == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Streak Recovery')),
        body: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    // Acceptance criterion: Recovery screen only shows in the broken-streak state
    // (current_streak is 0 and best_streak > 0)
    final isBroken = streak != null && streak.isStreakBroken;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Streak Recovery'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: isBroken
            ? _buildBrokenStreakRecoveryView(
                context,
                theme: theme,
                streakState: streakState,
                partnerName: partnerName,
                podId: podId,
              )
            : _buildNonBrokenStreakView(
                context,
                theme: theme,
                streak: streak,
                podId: podId,
              ),
      ),
    );
  }

  /// View shown when the streak is NOT broken.
  Widget _buildNonBrokenStreakView(
    BuildContext context, {
    required ThemeData theme,
    required dynamic streak,
    required String podId,
  }) {
    final currentStreak = streak?.currentStreak ?? 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Icon(
            Icons.check_circle_outline_rounded,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your Streak is Active!',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            currentStreak > 0
                ? 'You currently have a burning $currentStreak-day streak. Keep up the daily check-ins!'
                : 'No streak record has been set yet. Check in with your partner today to begin!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: () {
              context.push(
                AppRoutes.streakDetailPath,
                extra: podId,
              );
            },
            child: const Text('View Streak Details'),
          ),
        ],
      ),
    );
  }

  /// View shown strictly in the broken streak state (current == 0 && best > 0).
  Widget _buildBrokenStreakRecoveryView(
    BuildContext context, {
    required ThemeData theme,
    required PodStreakState streakState,
    required String partnerName,
    required String podId,
  }) {
    final streak = streakState.streak!;
    final bestStreak = streak.bestStreak;
    final meCheckedIn = streak.meCheckedInToday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Flame Illustration / Badge
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Encouraging Headline & Copy
        Text(
          'Let\'s Get Back on Track!',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Don\'t worry, every champion faces setbacks. You previously achieved an impressive streak of $bestStreak days! Team up with $partnerName to start a fresh streak today.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),

        // Best Record Card
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusLg,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.emoji_events_rounded,
                  color: theme.colorScheme.tertiary,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Record to Beat',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '$bestStreak Consecutive Days',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Action Steps Section
        Text(
          'Two steps to restart your streak:',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Step 1: Check in yourself
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: meCheckedIn
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(
              color: meCheckedIn
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                meCheckedIn
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: meCheckedIn
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. Log your check-in today',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      meCheckedIn
                          ? 'You are checked in for today!'
                          : 'Record your progress for today.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!meCheckedIn)
                FilledButton.tonal(
                  onPressed: () {
                    CheckInModal.show(
                      context,
                      podId: podId,
                      partnerName: partnerName,
                    );
                  },
                  child: const Text('Check In'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Step 2: Nudge partner
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2. Nudge $partnerName',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Send a push reminder to complete their check-in.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Feedback banner for nudge results
              if (streakState.nudgeStatus != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: streakState.nudgeSuccess == true
                        ? theme.colorScheme.primaryContainer
                        : (streakState.hasNudgeRateLimited
                            ? theme.colorScheme.secondaryContainer
                            : theme.colorScheme.errorContainer),
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        streakState.nudgeSuccess == true
                            ? Icons.check_circle_rounded
                            : (streakState.hasNudgeRateLimited
                                ? Icons.access_time_rounded
                                : Icons.error_outline_rounded),
                        size: 20,
                        color: streakState.nudgeSuccess == true
                            ? theme.colorScheme.onPrimaryContainer
                            : (streakState.hasNudgeRateLimited
                                ? theme.colorScheme.onSecondaryContainer
                                : theme.colorScheme.onErrorContainer),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          streakState.nudgeStatus!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: streakState.nudgeSuccess == true
                                ? theme.colorScheme.onPrimaryContainer
                                : (streakState.hasNudgeRateLimited
                                    ? theme.colorScheme.onSecondaryContainer
                                    : theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Nudge button
              FilledButton.icon(
                icon: streakState.isNudging
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.touch_app_rounded),
                label: const Text('Nudge your partner'),
                onPressed: streakState.isNudging ? null : _handleNudge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
