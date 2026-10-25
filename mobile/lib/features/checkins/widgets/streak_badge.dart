import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme/app_theme.dart';
import '../streak_provider.dart';

/// Embedded streak badge widget showing current_streak with a flame-style icon.
/// Tapping it routes to streak-detail (/streak-detail).
class StreakBadge extends ConsumerWidget {
  final String podId;
  final int? fallbackCurrentStreak;
  final int? fallbackBestStreak;
  final VoidCallback? onTap;

  const StreakBadge({
    super.key,
    required this.podId,
    this.fallbackCurrentStreak,
    this.fallbackBestStreak,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final streakState = ref.watch(podStreakProvider(podId));
    final streak = streakState.streak;

    final currentStreak =
        streak?.currentStreak ?? fallbackCurrentStreak ?? 0;
    final bestStreak = streak?.bestStreak ?? fallbackBestStreak ?? 0;

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.0),
      child: InkWell(
        borderRadius: AppRadius.borderRadiusLg,
        onTap: () {
          if (onTap != null) {
            onTap!();
          } else {
            context.push(
              AppRoutes.streakDetailPath,
              extra: podId,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: AppRadius.borderRadiusLg,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$currentStreak streak',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Best: $bestStreak',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
