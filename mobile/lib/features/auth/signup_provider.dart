import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/storage/token_storage.dart';
import 'auth_state.dart';
import 'models/user_model.dart';

class SignupState {
  final String name;
  final String email;
  final String password;
  final String confirmPassword;
  final bool isLoading;
  final String? errorMessage;
  final String? nameError;
  final String? emailError;
  final String? passwordError;
  final String? confirmPasswordError;

  const SignupState({
    this.name = '',
    this.email = '',
    this.password = '',
    this.confirmPassword = '',
    this.isLoading = false,
    this.errorMessage,
    this.nameError,
    this.emailError,
    this.passwordError,
    this.confirmPasswordError,
  });

  SignupState copyWith({
    String? name,
    String? email,
    String? password,
    String? confirmPassword,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? nameError,
    bool clearNameError = false,
    String? emailError,
    bool clearEmailError = false,
    String? passwordError,
    bool clearPasswordError = false,
    String? confirmPasswordError,
    bool clearConfirmPasswordError = false,
  }) {
    return SignupState(
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      nameError: clearNameError ? null : (nameError ?? this.nameError),
      emailError: clearEmailError ? null : (emailError ?? this.emailError),
      passwordError:
          clearPasswordError ? null : (passwordError ?? this.passwordError),
      confirmPasswordError: clearConfirmPasswordError
          ? null
          : (confirmPasswordError ?? this.confirmPasswordError),
    );
  }
}

class SignupNotifier extends Notifier<SignupState> {
  @override
  SignupState build() => const SignupState();

  void setName(String value) {
    state = state.copyWith(
      name: value,
      clearNameError: true,
      clearErrorMessage: true,
    );
  }

  void setEmail(String value) {
    state = state.copyWith(
      email: value,
      clearEmailError: true,
      clearErrorMessage: true,
    );
  }

  void setPassword(String value) {
    state = state.copyWith(
      password: value,
      clearPasswordError: true,
      clearErrorMessage: true,
    );
  }

  void setConfirmPassword(String value) {
    state = state.copyWith(
      confirmPassword: value,
      clearConfirmPasswordError: true,
      clearErrorMessage: true,
    );
  }

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> submit({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
    required BuildContext context,
  }) async {
    final name = state.name.trim();
    final email = state.email.trim();
    final password = state.password;
    final confirmPassword = state.confirmPassword;

    var hasClientError = false;
    String? nameErr;
    String? emailErr;
    String? passwordErr;
    String? confirmErr;

    if (name.isEmpty) {
      nameErr = 'Name is required';
      hasClientError = true;
    }

    if (email.isEmpty) {
      emailErr = 'Email is required';
      hasClientError = true;
    } else if (!email.contains('@')) {
      emailErr = 'Please enter a valid email address';
      hasClientError = true;
    }

    if (password.length < 8) {
      passwordErr = 'Password must be at least 8 characters long';
      hasClientError = true;
    }

    if (confirmPassword != password) {
      confirmErr = 'Passwords do not match';
      hasClientError = true;
    }

    if (hasClientError) {
      state = state.copyWith(
        nameError: nameErr,
        emailError: emailErr,
        passwordError: passwordErr,
        confirmPasswordError: confirmErr,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearNameError: true,
      clearEmailError: true,
      clearPasswordError: true,
      clearConfirmPasswordError: true,
    );

    try {
      String timezone = 'UTC';
      try {
        final tzInfo = await FlutterTimezone.getLocalTimezone();
        if (tzInfo.identifier.isNotEmpty) {
          timezone = tzInfo.identifier;
        }
      } catch (_) {
        timezone = 'UTC';
      }

      final response = await apiClient.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'timezone': timezone,
        },
      );

      final token = response.data['token'] as String;
      final userData = response.data['user'] as Map<String, dynamic>;
      final user = UserModel.fromJson(userData);

      await tokenStorage.saveToken(token);
      ref.read(authNotifierProvider.notifier).setAuthenticated(user);

      state = state.copyWith(isLoading: false);

      if (context.mounted) {
        context.go(AppRoutes.profileSetupPath);
      }
    } on ApiException catch (e) {
      String? inlineEmailErr;
      String? inlineNameErr;
      String? inlinePassErr;

      final msg = e.message.toLowerCase();
      if (msg.contains('email') || e.code == 'EMAIL_EXISTS') {
        inlineEmailErr = e.message;
      } else if (msg.contains('name')) {
        inlineNameErr = e.message;
      } else if (msg.contains('password')) {
        inlinePassErr = e.message;
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
        emailError: inlineEmailErr,
        nameError: inlineNameErr,
        passwordError: inlinePassErr,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An unexpected error occurred during sign up.',
      );
    }
  }
}

final signupNotifierProvider =
    NotifierProvider<SignupNotifier, SignupState>(SignupNotifier.new);
