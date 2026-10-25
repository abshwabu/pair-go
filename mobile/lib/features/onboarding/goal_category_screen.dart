import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/onboarding_step_header.dart';
import 'goal_category_provider.dart';

class GoalCategoryScreen extends ConsumerWidget {
  const GoalCategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedCategory = ref.watch(selectedGoalCategoryProvider);

    void selectAndNavigate(String key) {
      HapticFeedback.lightImpact();
      ref.read(selectedGoalCategoryProvider.notifier).select(key);
      context.go(AppRoutes.goalDetailPath);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal Category'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OnboardingStepHeader(
                    currentStep: 2,
                    totalSteps: 4,
                    onBack: () => context.pop(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                        Text(
                          'What is your main focus?',
                          style: AppTypography.headlineLarge.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Select a category to be paired with an accountability partner who shares your commitment.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // 2-Column Grid of rich category cards
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final cardWidth = (constraints.maxWidth - AppSpacing.sm) / 2;

                            return Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: kGoalCategories.map((item) {
                                final isSelected = selectedCategory == item.key;
                                final isCustom = item.key == 'custom';
                                final effectiveWidth = isCustom
                                    ? constraints.maxWidth
                                    : cardWidth;

                                return SizedBox(
                                  width: effectiveWidth,
                                  child: AppCard(
                                    onTap: () => selectAndNavigate(item.key),
                                    isSelected: isSelected,
                                    padding: const EdgeInsets.all(AppSpacing.md),
                                    child: AnimatedContainer(
                                      duration: AppMotion.shortDuration,
                                      curve: AppMotion.easeOutCubic,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : colorScheme
                                                          .primaryContainer,
                                                  borderRadius:
                                                      AppRadius.borderRadiusSm,
                                                ),
                                                child: Icon(
                                                  item.icon,
                                                  color: isSelected
                                                      ? colorScheme.onPrimary
                                                      : colorScheme.primary,
                                                  size: 24,
                                                ),
                                              ),
                                              if (isSelected)
                                                Icon(
                                                  Icons.check_circle_rounded,
                                                  color: colorScheme.primary,
                                                  size: 20,
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: AppSpacing.md),
                                          Text(
                                            item.title,
                                            style: AppTypography.titleMedium
                                                .copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(
                                              height: AppSpacing.xxs),
                                          Text(
                                            item.description,
                                            style: AppTypography.bodySmall
                                                .copyWith(
                                              color: colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // Pinned Continue Button
                        AppButton.primary(
                          label: 'Continue',
                          onPressed: selectedCategory != null
                              ? () => selectAndNavigate(selectedCategory)
                              : null,
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
