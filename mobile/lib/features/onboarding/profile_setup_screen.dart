import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/dialog_helpers.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/onboarding_step_header.dart';
import '../auth/auth_state.dart';
import 'profile_setup_provider.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  final bool isEditing;

  const ProfileSetupScreen({
    super.key,
    this.isEditing = false,
  });

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final ImagePicker _picker = ImagePicker();

  static const List<String> _commonTimezones = [
    'UTC',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Toronto',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Europe/Amsterdam',
    'Africa/Addis_Ababa',
    'Africa/Nairobi',
    'Africa/Cairo',
    'Africa/Johannesburg',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Singapore',
    'Asia/Tokyo',
    'Australia/Sydney',
  ];

  static const Map<String, String> _languages = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'am': 'Amharic',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ar': 'Arabic',
  };

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final user = ref.read(currentUserProvider);
        if (user != null) {
          ref.read(profileSetupNotifierProvider.notifier).loadUser(user);
        }
      });
    }
  }

  Future<void> _pickAvatar() async {
    HapticFeedback.lightImpact();
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        ref.read(profileSetupNotifierProvider.notifier).setAvatar(image);
      }
    } catch (_) {
      // Ignored if cancelled
    }
  }

  void _showTimezonePicker(BuildContext context, String currentTimezone) {
    HapticFeedback.lightImpact();
    showAppBottomSheet<void>(
      context: context,
      title: 'Select Timezone',
      builder: (bottomSheetContext) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colorScheme = Theme.of(context).colorScheme;
            final filtered = _commonTimezones
                .where((tz) =>
                    tz.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search timezone...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val;
                      });
                    },
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final tz = filtered[index];
                      final isSelected = tz == currentTimezone;
                      return ListTile(
                        title: Text(
                          tz,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.normal,
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
                          ref
                              .read(profileSetupNotifierProvider.notifier)
                              .setTimezone(tz);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLanguagePicker(BuildContext context, String currentLanguage) {
    HapticFeedback.lightImpact();
    showAppBottomSheet<void>(
      context: context,
      title: 'Select Language',
      builder: (bottomSheetContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return ListView(
          shrinkWrap: true,
          children: _languages.entries.map((entry) {
            final isSelected = entry.key == currentLanguage;
            return ListTile(
              title: Text(
                entry.value,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                entry.key.toUpperCase(),
                style: AppTypography.bodySmall.copyWith(
                  color: colorScheme.onSurfaceVariant,
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
                ref
                    .read(profileSetupNotifierProvider.notifier)
                    .setLanguage(entry.key);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        );
      },
    );
  }

  void _submit() {
    HapticFeedback.lightImpact();
    ref.read(profileSetupNotifierProvider.notifier).submit(
          apiClient: ref.read(apiClientProvider),
          context: context,
          isEditing: widget.isEditing,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(profileSetupNotifierProvider);
    final notifier = ref.read(profileSetupNotifierProvider.notifier);

    ImageProvider? avatarImage;
    if (state.avatarFile != null && !kIsWeb) {
      avatarImage = FileImage(File(state.avatarFile!.path));
    } else if (state.existingAvatarUrl != null &&
        state.existingAvatarUrl!.isNotEmpty) {
      avatarImage = NetworkImage(state.existingAvatarUrl!);
    }

    final languageDisplayName =
        _languages[state.language] ?? state.language.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Profile' : 'Profile Setup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.isEditing) ...[
                    const OnboardingStepHeader(
                      currentStep: 1,
                      totalSteps: 4,
                      showBackButton: false,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Text(
                          widget.isEditing
                              ? 'Edit your profile'
                              : 'Complete your profile',
                          style: AppTypography.headlineLarge.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          widget.isEditing
                              ? 'Update your photo, name, timezone, and language'
                              : 'Add your photo and verify your timezone for pairing',
                          style: AppTypography.bodyMedium.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // Error Banner
                        if (state.errorMessage != null) ...[
                          ErrorBanner(
                            message: state.errorMessage,
                            onDismiss: notifier.clearErrorMessage,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // Avatar Picker
                        Center(
                          child: GestureDetector(
                            onTap: state.isLoading ? null : _pickAvatar,
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                AppAvatar(
                                  size: AppAvatarSize.xl,
                                  image: avatarImage,
                                  name: state.name.isNotEmpty
                                      ? state.name
                                      : 'Pair',
                                ),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colorScheme.surface,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.shadow
                                            .withValues(alpha: 0.15),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.camera_alt_rounded,
                                    size: 18,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // Name Field
                        AppTextField(
                          initialValue: state.name,
                          label: 'Display Name',
                          hint: 'Your name',
                          prefixIcon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          error: state.nameError,
                          onChanged: notifier.setName,
                          enabled: !state.isLoading,
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Timezone Selector
                        InkWell(
                          onTap: state.isLoading
                              ? null
                              : () => _showTimezonePicker(
                                    context,
                                    state.timezone,
                                  ),
                          borderRadius: AppRadius.borderRadiusInput,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Timezone',
                              prefixIcon: Icon(Icons.schedule_rounded),
                              suffixIcon:
                                  Icon(Icons.arrow_drop_down_rounded),
                            ),
                            child: Text(
                              state.timezone,
                              style: AppTypography.bodyLarge.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Language Selector
                        InkWell(
                          onTap: state.isLoading
                              ? null
                              : () => _showLanguagePicker(
                                    context,
                                    state.language,
                                  ),
                          borderRadius: AppRadius.borderRadiusInput,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Language',
                              prefixIcon: Icon(Icons.language_rounded),
                              suffixIcon:
                                  Icon(Icons.arrow_drop_down_rounded),
                            ),
                            child: Text(
                              languageDisplayName,
                              style: AppTypography.bodyLarge.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // Continue / Save Changes Button
                        AppButton.primary(
                          label: widget.isEditing
                              ? 'Save Changes'
                              : 'Continue to Goals',
                          isLoading: state.isLoading,
                          onPressed: state.isLoading ? null : _submit,
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
