import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
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
    final tokens = context.tokens;
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
                    borderRadius: AppRadius.borderRadiusCard,
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
                              style: AppTypography.titleMedium.copyWith(
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
                        style: AppTypography.bodyMedium.copyWith(
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
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: tokens.flameBackground,
                        borderRadius: AppRadius.borderRadiusCard,
                        border: Border.all(
                          color: tokens.flame.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 38,
                            color: tokens.flame,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '${streak?.currentStreak ?? 0}',
                            style: AppTypography.headlineLarge.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Current Streak',
                            style: AppTypography.labelMedium.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: AppRadius.borderRadiusCard,
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            size: 38,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '${streak?.bestStreak ?? 0}',
                            style: AppTypography.headlineLarge.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Best Streak',
                            style: AppTypography.labelMedium.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusCard,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today\'s Accountability',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Streaks increase when both members complete their daily check-in (UTC).',
                        style: AppTypography.bodySmall.copyWith(
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

              // Calendar Heatmap & Legend Section
              _buildHeatmapSection(context, streakState.history, theme, tokens),
              const SizedBox(height: AppSpacing.xl),

              // 3. History List Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Check-in History',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
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
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.borderRadiusCard,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'No check-ins recorded yet.\nCheck in today to start your streak!',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
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

  Widget _buildHeatmapSection(
    BuildContext context,
    List<DailyCheckInItem> history,
    ThemeData theme,
    AppColorsExtension tokens,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusCard,
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Activity Heatmap',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Heatmap grid (last 14 days or available items)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(14, (idx) {
              final item = idx < history.length ? history[idx] : null;
              final both = item?.bothCheckedIn ?? false;
              final one = (item != null && !both && item.memberIds.isNotEmpty);

              Color cellColor = theme.colorScheme.surfaceContainerHigh;
              if (both) {
                cellColor = tokens.flame;
              } else if (one) {
                cellColor = tokens.warning;
              }

              return Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: cellColor,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          // Legend
          Row(
            children: [
              _buildLegendDot(tokens.flame, 'Both', theme),
              const SizedBox(width: AppSpacing.md),
              _buildLegendDot(tokens.warning, 'Partial', theme),
              const SizedBox(width: AppSpacing.md),
              _buildLegendDot(
                theme.colorScheme.surfaceContainerHigh,
                'None',
                theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
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
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
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
            style: AppTypography.labelSmall.copyWith(
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
        borderRadius: AppRadius.borderRadiusCard,
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
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  bothCompleted
                      ? 'Both members completed check-in'
                      : '1 member completed check-in',
                  style: AppTypography.bodySmall.copyWith(
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
              style: AppTypography.labelSmall.copyWith(
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
