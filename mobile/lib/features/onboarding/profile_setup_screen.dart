import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import 'profile_setup_provider.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

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

  Future<void> _pickAvatar() async {
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
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (bottomSheetContext) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _commonTimezones
                .where((tz) =>
                    tz.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(context).dividerColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Select Timezone',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
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
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final tz = filtered[index];
                          final isSelected = tz == currentTimezone;
                          return ListTile(
                            title: Text(tz),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  )
                                : null,
                            onTap: () {
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(profileSetupNotifierProvider);
    final notifier = ref.read(profileSetupNotifierProvider.notifier);

    ImageProvider? avatarImage;
    if (state.avatarFile != null && !kIsWeb) {
      avatarImage = FileImage(File(state.avatarFile!.path));
    } else if (state.existingAvatarUrl != null &&
        state.existingAvatarUrl!.isNotEmpty) {
      avatarImage = NetworkImage(state.existingAvatarUrl!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Setup'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Complete your profile',
                    style: theme.textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Add your photo and verify your timezone for pairing',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Error Banner
                  if (state.errorMessage != null)
                    ErrorBanner(
                      message: state.errorMessage,
                      onDismiss: notifier.clearErrorMessage,
                    ),

                  // Avatar Picker
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 54,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? Icon(
                                  Icons.person_rounded,
                                  size: 56,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Material(
                            color: theme.colorScheme.primary,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: InkWell(
                              onTap: state.isLoading ? null : _pickAvatar,
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                child: Icon(
                                  Icons.camera_alt_rounded,
                                  size: 20,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Name Field
                  TextFormField(
                    initialValue: state.name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Display Name',
                      hintText: 'Your name',
                      prefixIcon: const Icon(Icons.person_outline),
                      errorText: state.nameError,
                    ),
                    onChanged: notifier.setName,
                    enabled: !state.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Timezone Selector
                  InkWell(
                    onTap: state.isLoading
                        ? null
                        : () => _showTimezonePicker(context, state.timezone),
                    borderRadius: AppRadius.borderRadiusMd,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        prefixIcon: Icon(Icons.schedule_rounded),
                        suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                      ),
                      child: Text(
                        state.timezone,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Continue Button
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
                        : const Text('Continue to Goals'),
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
