import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/dialog_helpers.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/onboarding_step_header.dart';
import 'matching_prefs_provider.dart';

class MatchingPrefsScreen extends ConsumerWidget {
  const MatchingPrefsScreen({super.key});

  static const List<Map<String, String>> _availableLanguages = [
    {'code': 'en', 'name': 'English'},
    {'code': 'es', 'name': 'Spanish (Español)'},
    {'code': 'fr', 'name': 'French (Français)'},
    {'code': 'de', 'name': 'German (Deutsch)'},
    {'code': 'am', 'name': 'Amharic (አማርኛ)'},
    {'code': 'ar', 'name': 'Arabic (العربية)'},
    {'code': 'zh', 'name': 'Chinese (中文)'},
    {'code': 'ja', 'name': 'Japanese (日本語)'},
    {'code': 'pt', 'name': 'Portuguese (Português)'},
  ];

  String _getToleranceLabel(int hours) {
    if (hours == 0) return 'Exact match (same hour)';
    if (hours == 12) return 'Anywhere in the world';
    return 'Within $hours hours of me';
  }

  void _showLanguagePicker(
    BuildContext context,
    String currentLanguage,
    MatchingPrefsNotifier notifier,
  ) {
    HapticFeedback.lightImpact();
    showAppBottomSheet<void>(
      context: context,
      title: 'Select Language',
      builder: (bottomSheetContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return ListView(
          shrinkWrap: true,
          children: _availableLanguages.map((lang) {
            final isSelected = lang['code'] == currentLanguage;
            return ListTile(
              title: Text(
                lang['name']!,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: colorScheme.primary,
                    )
                  : null,
              onTap: () {
                HapticFeedback.lightImpact();
                notifier.setLanguage(lang['code']!);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(matchingPrefsNotifierProvider);
    final notifier = ref.read(matchingPrefsNotifierProvider.notifier);

    final currentLangMap = _availableLanguages.firstWhere(
      (l) => l['code'] == state.language,
      orElse: () => {'code': 'en', 'name': 'English'},
    );

    void submit() {
      HapticFeedback.lightImpact();
      notifier.saveAndProceed(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matching Preferences'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OnboardingStepHeader(
                    currentStep: 4,
                    totalSteps: 4,
                    onBack: () => context.pop(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Partner Preferences',
                          style: AppTypography.headlineLarge.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Set your availability tolerance and communication language to find the ideal accountability match.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        if (state.errorMessage != null) ...[
                          ErrorBanner(
                            message: state.errorMessage,
                            onDismiss: notifier.clearErrorMessage,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // Timezone Tolerance Card
                        AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Timezone Tolerance',
                                    style: AppTypography.titleMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius:
                                          AppRadius.borderRadiusFull,
                                    ),
                                    child: Text(
                                      state.timezoneToleranceHours == 0
                                          ? 'Exact'
                                          : '± ${state.timezoneToleranceHours}h',
                                      style: AppTypography.labelSmall.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                _getToleranceLabel(
                                    state.timezoneToleranceHours),
                                style: AppTypography.bodySmall.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Slider(
                                value:
                                    state.timezoneToleranceHours.toDouble(),
                                min: 0,
                                max: 12,
                                divisions: 12,
                                label:
                                    '± ${state.timezoneToleranceHours}h',
                                onChanged: (val) {
                                  notifier.setTimezoneTolerance(val.round());
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '0 hrs',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      '6 hrs',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      '12 hrs',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Language Preference Card
                        AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preferred Language',
                                style: AppTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Language for check-ins, messages, and accountability chat.',
                                style: AppTypography.bodySmall.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              InkWell(
                                onTap: state.isLoading
                                    ? null
                                    : () => _showLanguagePicker(
                                          context,
                                          state.language,
                                          notifier,
                                        ),
                                borderRadius: AppRadius.borderRadiusInput,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    prefixIcon:
                                        Icon(Icons.language_rounded),
                                    labelText: 'Language',
                                    suffixIcon:
                                        Icon(Icons.arrow_drop_down_rounded),
                                  ),
                                  child: Text(
                                    currentLangMap['name']!,
                                    style: AppTypography.bodyLarge.copyWith(
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // Find Match Button
                        AppButton.primary(
                          label: 'Find Partner Match',
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
