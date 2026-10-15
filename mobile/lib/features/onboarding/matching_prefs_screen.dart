import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(matchingPrefsNotifierProvider);
    final notifier = ref.read(matchingPrefsNotifierProvider.notifier);

    final currentLangCode = _availableLanguages
            .any((l) => l['code'] == state.language)
        ? state.language
        : 'en';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matching Preferences'),
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
                    'Partner Preferences',
                    style: theme.textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Set your availability tolerance and communication language to find the ideal accountability match.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  if (state.errorMessage != null)
                    ErrorBanner(
                      message: state.errorMessage,
                      onDismiss: notifier.clearErrorMessage,
                    ),

                  // Timezone Tolerance Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusMd,
                      side: BorderSide(color: theme.dividerColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Timezone Tolerance',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xxs,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: AppRadius.borderRadiusSm,
                                ),
                                child: Text(
                                  state.timezoneToleranceHours == 0
                                      ? 'Same hour'
                                      : '± ${state.timezoneToleranceHours} hrs',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Maximum hours difference between your timezone and your partner.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Slider(
                            value: state.timezoneToleranceHours.toDouble(),
                            min: 0,
                            max: 12,
                            divisions: 12,
                            label: '± ${state.timezoneToleranceHours}h',
                            onChanged: (val) {
                              notifier.setTimezoneTolerance(val.round());
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('0 hrs', style: theme.textTheme.labelSmall),
                                Text('6 hrs', style: theme.textTheme.labelSmall),
                                Text('12 hrs',
                                    style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Language Preference Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusMd,
                      side: BorderSide(color: theme.dividerColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preferred Language',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Language for check-ins, messages, and accountability chat.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          DropdownButtonFormField<String>(
                            initialValue: currentLangCode,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.language_rounded),
                              labelText: 'Language',
                            ),
                            items: _availableLanguages.map((lang) {
                              return DropdownMenuItem<String>(
                                value: lang['code'],
                                child: Text(lang['name']!),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                notifier.setLanguage(val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Find Match Button
                  ElevatedButton(
                    onPressed: state.isLoading
                        ? null
                        : () => notifier.saveAndProceed(context),
                    child: const Text('Find Partner Match'),
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
