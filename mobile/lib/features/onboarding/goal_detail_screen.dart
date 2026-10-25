import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/onboarding_step_header.dart';
import 'goal_category_provider.dart';
import 'goal_detail_provider.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key});

  String _getPromptTitle(String category) {
    switch (category.toLowerCase()) {
      case 'read':
        return 'What are you going to read?';
      case 'watch':
        return 'What are you planning to watch?';
      case 'fitness':
        return 'What are you training for?';
      case 'habit':
        return 'What habit are you building?';
      default:
        return 'Define your goal';
    }
  }

  String _getPaceDescription(String pace) {
    switch (pace.toLowerCase()) {
      case 'relaxed':
        return '1–2 check-ins a week • Low pressure, flexible pace';
      case 'intense':
        return 'Daily check-ins • High accountability & rapid momentum';
      case 'steady':
      default:
        return '3–5 check-ins a week • Balanced, consistent progress';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final category = ref.watch(selectedGoalCategoryProvider) ?? 'custom';
    final state = ref.watch(goalDetailNotifierProvider);
    final notifier = ref.read(goalDetailNotifierProvider.notifier);

    void submit() {
      HapticFeedback.lightImpact();
      notifier.submit(
        apiClient: ref.read(apiClientProvider),
        context: context,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal Details'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OnboardingStepHeader(
                    currentStep: 3,
                    totalSteps: 4,
                    onBack: () => context.pop(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _getPromptTitle(category),
                    style: AppTypography.headlineLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Your accountability partner will see this to track progress with you.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Category Badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusFull,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Category: ${category.toUpperCase()}',
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Error Banner
                  if (state.errorMessage != null) ...[
                    ErrorBanner(
                      message: state.errorMessage,
                      onDismiss: notifier.clearErrorMessage,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Title Field
                  AppTextField(
                    initialValue: state.title,
                    label: 'Goal Title',
                    hint: 'e.g. Run 5k Daily',
                    prefixIcon: Icons.flag_outlined,
                    textInputAction: TextInputAction.next,
                    error: state.titleError,
                    onChanged: notifier.setTitle,
                    enabled: !state.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Target Description Field
                  AppTextField(
                    initialValue: state.targetDescription,
                    label: 'Target Description',
                    hint:
                        'Describe what you plan to accomplish (e.g. 25 pages daily, finish in 3 weeks)',
                    prefixIcon: Icons.notes_rounded,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    onChanged: notifier.setTargetDescription,
                    enabled: !state.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Pace Section
                  Text(
                    'Target Pace',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'How aggressively do you want to pursue this goal?',
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'relaxed',
                        label: Text('Relaxed'),
                        icon: Icon(Icons.wb_sunny_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'steady',
                        label: Text('Steady'),
                        icon: Icon(Icons.directions_walk_rounded),
                      ),
                      ButtonSegment<String>(
                        value: 'intense',
                        label: Text('Intense'),
                        icon: Icon(Icons.local_fire_department_outlined),
                      ),
                    ],
                    selected: {state.pace},
                    onSelectionChanged: state.isLoading
                        ? null
                        : (Set<String> newSelection) {
                            HapticFeedback.lightImpact();
                            notifier.setPace(newSelection.first);
                          },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _getPaceDescription(state.pace),
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Submit Button
                  AppButton.primary(
                    label: 'Save & Continue to Matching',
                    isLoading: state.isLoading,
                    onPressed: state.isLoading ? null : submit,
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
