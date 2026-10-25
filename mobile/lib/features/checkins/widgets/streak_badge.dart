import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../core/theme/app_typography.dart';
import '../streak_provider.dart';

/// Embedded streak badge widget showing current_streak with a flame-style icon
/// and a gentle pulse animation. Tapping it routes to streak-detail (/streak-detail).
class StreakBadge extends ConsumerStatefulWidget {
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
  ConsumerState<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends ConsumerState<StreakBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // In widget tests, avoid infinite repeat so pumpAndSettle does not time out
    final isRunningTests = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isRunningTests) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final disableMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final streakState = ref.watch(podStreakProvider(widget.podId));
    final streak = streakState.streak;

    final currentStreak =
        streak?.currentStreak ?? widget.fallbackCurrentStreak ?? 0;
    final bestStreak = streak?.bestStreak ?? widget.fallbackBestStreak ?? 0;

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.0),
      child: InkWell(
        borderRadius: AppRadius.borderRadiusLg,
        onTap: () {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            context.push(
              AppRoutes.streakDetailPath,
              extra: widget.podId,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: tokens.flameBackground,
            borderRadius: AppRadius.borderRadiusLg,
            border: Border.all(
              color: tokens.flame.withValues(alpha: 0.25),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              disableMotion
                  ? Icon(
                      Icons.local_fire_department_rounded,
                      color: tokens.flame,
                      size: 24,
                    )
                  : ScaleTransition(
                      scale: _pulseAnimation,
                      child: Icon(
                        Icons.local_fire_department_rounded,
                        color: tokens.flame,
                        size: 24,
                      ),
                    ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$currentStreak streak',
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Best: $bestStreak',
                    style: AppTypography.labelSmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
