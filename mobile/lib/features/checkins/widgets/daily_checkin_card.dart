import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: AppRadius.borderRadiusLg,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.borderRadiusLg,
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
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.flag_rounded,
                      color: theme.colorScheme.onPrimary,
                      size: 20,
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
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
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
                                color: theme.colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.6),
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Text(
                              'Tap to check in',
                              style: theme.textTheme.labelMedium?.copyWith(
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
