import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import 'goal_category_provider.dart';
import 'goal_detail_provider.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final category = ref.watch(selectedGoalCategoryProvider) ?? 'custom';
    final state = ref.watch(goalDetailNotifierProvider);
    final notifier = ref.read(goalDetailNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal Details'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Define your goal',
                    style: theme.textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Your accountability partner will see this to track progress with you.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Category Badge
                  Center(
                    child: Chip(
                      avatar: Icon(
                        Icons.category_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      label: Text(
                        'Category: ${category.toUpperCase()}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      backgroundColor: theme.colorScheme.primaryContainer,
                      side: BorderSide.none,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Error Banner
                  if (state.errorMessage != null)
                    ErrorBanner(
                      message: state.errorMessage,
                      onDismiss: notifier.clearErrorMessage,
                    ),

                  // Title Field
                  TextFormField(
                    initialValue: state.title,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: 'Goal Title',
                      hintText: 'e.g. Read Clean Architecture',
                      prefixIcon: const Icon(Icons.flag_outlined),
                      errorText: state.titleError,
                    ),
                    onChanged: notifier.setTitle,
                    enabled: !state.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Target Description Field
                  TextFormField(
                    initialValue: state.targetDescription,
                    minLines: 3,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Target Description',
                      hintText:
                          'Describe what you plan to accomplish (e.g. 25 pages daily, finish in 3 weeks)',
                      alignLabelWithHint: true,
                    ),
                    onChanged: notifier.setTargetDescription,
                    enabled: !state.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Pace Segmented Button
                  Text(
                    'Target Pace',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'How aggressively do you want to pursue this goal?',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
                            notifier.setPace(newSelection.first);
                          },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Submit Button
                  ElevatedButton(
                    onPressed: state.isLoading
                        ? null
                        : () => notifier.submit(
                              apiClient: ref.read(apiClientProvider),
                              context: context,
                            ),
                    child: state.isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Save & Continue to Matching'),
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
