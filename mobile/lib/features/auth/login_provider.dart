import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import 'auth_navigation.dart';
import 'auth_state.dart';
import 'models/user_model.dart';

class LoginState {
  final String email;
  final String password;
  final bool isLoading;
  final String? errorMessage;
  final String? emailError;
  final String? passwordError;

  const LoginState({
    this.email = '',
    this.password = '',
    this.isLoading = false,
    this.errorMessage,
    this.emailError,
    this.passwordError,
  });

  LoginState copyWith({
    String? email,
    String? password,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? emailError,
    bool clearEmailError = false,
    String? passwordError,
    bool clearPasswordError = false,
  }) {
    return LoginState(
      email: email ?? this.email,
      password: password ?? this.password,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      emailError: clearEmailError ? null : (emailError ?? this.emailError),
      passwordError:
          clearPasswordError ? null : (passwordError ?? this.passwordError),
    );
  }
}

class LoginNotifier extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState();

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

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> submit({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
    required BuildContext context,
  }) async {
    final email = state.email.trim();
    final password = state.password;

    var hasClientError = false;
    String? emailErr;
    String? passwordErr;

    if (email.isEmpty) {
      emailErr = 'Email is required';
      hasClientError = true;
    } else if (!email.contains('@')) {
      emailErr = 'Please enter a valid email address';
      hasClientError = true;
    }

    if (password.isEmpty) {
      passwordErr = 'Password is required';
      hasClientError = true;
    }

    if (hasClientError) {
      state = state.copyWith(
        emailError: emailErr,
        passwordError: passwordErr,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearEmailError: true,
      clearPasswordError: true,
    );

    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      final token = response.data['token'] as String;
      final userData = response.data['user'] as Map<String, dynamic>;
      final user = UserModel.fromJson(userData);

      await tokenStorage.saveToken(token);
      ref.read(authNotifierProvider.notifier).setAuthenticated(user);

      state = state.copyWith(isLoading: false);

      if (context.mounted) {
        await navigatePostAuth(
          apiClient: apiClient,
          tokenStorage: tokenStorage,
          context: context,
          onAuthenticated: (u) {
            ref.read(authNotifierProvider.notifier).setAuthenticated(u);
          },
          onLogout: () {
            ref.read(authNotifierProvider.notifier).logout();
          },
        );
      }
    } on ApiException catch (e) {
      String? inlineEmailErr;
      String? inlinePassErr;

      final msg = e.message.toLowerCase();
      if (msg.contains('email')) {
        inlineEmailErr = e.message;
      } else if (msg.contains('password')) {
        inlinePassErr = e.message;
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
        emailError: inlineEmailErr,
        passwordError: inlinePassErr,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An unexpected error occurred. Please try again.',
      );
    }
  }
}

final loginNotifierProvider =
    NotifierProvider<LoginNotifier, LoginState>(LoginNotifier.new);
