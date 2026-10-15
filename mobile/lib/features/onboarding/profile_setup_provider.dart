import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../auth/auth_state.dart';
import '../auth/models/user_model.dart';

class ProfileSetupState {
  final String name;
  final String timezone;
  final XFile? avatarFile;
  final String? existingAvatarUrl;
  final bool isLoading;
  final String? errorMessage;
  final String? nameError;

  const ProfileSetupState({
    this.name = '',
    this.timezone = 'UTC',
    this.avatarFile,
    this.existingAvatarUrl,
    this.isLoading = false,
    this.errorMessage,
    this.nameError,
  });

  ProfileSetupState copyWith({
    String? name,
    String? timezone,
    XFile? avatarFile,
    String? existingAvatarUrl,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? nameError,
    bool clearNameError = false,
  }) {
    return ProfileSetupState(
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      avatarFile: avatarFile ?? this.avatarFile,
      existingAvatarUrl: existingAvatarUrl ?? this.existingAvatarUrl,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      nameError: clearNameError ? null : (nameError ?? this.nameError),
    );
  }
}

class ProfileSetupNotifier extends Notifier<ProfileSetupState> {
  @override
  ProfileSetupState build() {
    final currentUser = ref.watch(currentUserProvider);
    final initialName = currentUser?.name ?? '';
    final initialTimezone = currentUser?.timezone ?? 'UTC';
    final initialAvatarUrl = currentUser?.avatarUrl;

    // Detect device timezone asynchronously if available
    _detectDeviceTimezone();

    return ProfileSetupState(
      name: initialName,
      timezone: initialTimezone,
      existingAvatarUrl: initialAvatarUrl,
    );
  }

  Future<void> _detectDeviceTimezone() async {
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      if (tzInfo.identifier.isNotEmpty && state.timezone == 'UTC') {
        state = state.copyWith(timezone: tzInfo.identifier);
      }
    } catch (_) {
      // Keep default timezone if detection fails
    }
  }

  void setName(String value) {
    state = state.copyWith(
      name: value,
      clearNameError: true,
      clearErrorMessage: true,
    );
  }

  void setTimezone(String value) {
    state = state.copyWith(
      timezone: value,
      clearErrorMessage: true,
    );
  }

  void setAvatar(XFile file) {
    state = state.copyWith(
      avatarFile: file,
      clearErrorMessage: true,
    );
  }

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> submit({
    required ApiClient apiClient,
    required BuildContext context,
  }) async {
    final name = state.name.trim();
    if (name.isEmpty) {
      state = state.copyWith(nameError: 'Name cannot be empty');
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearNameError: true,
    );

    try {
      // 1. Upload avatar if selected
      if (state.avatarFile != null) {
        final file = state.avatarFile!;
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            file.path,
            filename: file.name.isNotEmpty ? file.name : 'avatar.jpg',
          ),
        });

        await apiClient.post<Map<String, dynamic>>(
          '/profile/avatar',
          data: formData,
        );
      }

      // 2. Save profile updates via PATCH /profile
      final response = await apiClient.patch<Map<String, dynamic>>(
        '/profile',
        data: {
          'name': name,
          'timezone': state.timezone,
        },
      );

      final updatedUser = UserModel.fromJson(response.data);
      ref.read(authNotifierProvider.notifier).setUser(updatedUser);

      state = state.copyWith(isLoading: false);

      if (context.mounted) {
        context.go(AppRoutes.goalCategoryPath);
      }
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to update profile. Please try again.',
      );
    }
  }
}

final profileSetupNotifierProvider =
    NotifierProvider<ProfileSetupNotifier, ProfileSetupState>(
  ProfileSetupNotifier.new,
);
