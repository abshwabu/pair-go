import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../core/theme/app_typography.dart';
import '../streak_provider.dart';
import 'checkin_modal.dart';

/// Dismissible card shown at the top of Pod Home when me_checked_in_today is false.
/// Tapping it opens [CheckInModal].
class DailyCheckinCard extends ConsumerWidget {
  final String podId;
  final String? partnerName;

  const DailyCheckinCard({
    super.key,
    required this.podId,
    this.partnerName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final streakState = ref.watch(podStreakProvider(podId));

    if (!streakState.shouldShowDailyPrompt) {
      return const SizedBox.shrink();
    }

    final partner = partnerName ?? 'Partner';
    final partnerDone = streakState.streak?.partnerCheckedInToday ?? false;

    return Dismissible(
      key: ValueKey('daily_checkin_prompt_$podId'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        ref.read(podStreakProvider(podId).notifier).dismissDailyPrompt();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: AppRadius.borderRadiusCard,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.0),
          child: InkWell(
            borderRadius: AppRadius.borderRadiusCard,
            onTap: () {
              CheckInModal.show(
                context,
                podId: podId,
                partnerName: partner,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tokens.flameBackground,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tokens.flame.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      color: tokens.flame,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Daily Check-in',
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              tooltip: 'Dismiss',
                              onPressed: () {
                                ref
                                    .read(podStreakProvider(podId).notifier)
                                    .dismissDailyPrompt();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          partnerDone
                              ? '$partner already checked in! Complete yours to advance your streak.'
                              : 'Keep your streak alive. Tap to log your progress for today.',
                          style: AppTypography.bodySmall.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Text(
                              'Tap to check in',
                              style: AppTypography.labelMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
