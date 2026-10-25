import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/error_banner.dart';
import 'login_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  void _submit() {
    HapticFeedback.lightImpact();
    ref.read(loginNotifierProvider.notifier).submit(
          apiClient: ref.read(apiClientProvider),
          tokenStorage: ref.read(tokenStorageProvider),
          context: context,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loginState = ref.watch(loginNotifierProvider);
    final loginNotifier = ref.read(loginNotifierProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusLg,
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 32,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Welcome back',
                    style: AppTypography.headlineLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Pick up where you left off with your partner.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Error Banner
                  if (loginState.errorMessage != null) ...[
                    ErrorBanner(
                      message: loginState.errorMessage,
                      onDismiss: loginNotifier.clearErrorMessage,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Email Field
                  AppTextField(
                    initialValue: loginState.email,
                    label: 'Email',
                    hint: 'you@example.com',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    error: loginState.emailError,
                    onChanged: loginNotifier.setEmail,
                    enabled: !loginState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Password Field
                  AppTextField(
                    initialValue: loginState.password,
                    label: 'Password',
                    hint: '••••••••',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    error: loginState.passwordError,
                    onChanged: loginNotifier.setPassword,
                    onSubmitted: (_) {
                      if (!loginState.isLoading) {
                        _submit();
                      }
                    },
                    enabled: !loginState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Primary Submit Button
                  AppButton.primary(
                    label: 'Log In',
                    isLoading: loginState.isLoading,
                    onPressed: loginState.isLoading ? null : _submit,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Link to Sign Up
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: AppTypography.bodyMedium.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: loginState.isLoading
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                context.go(AppRoutes.signupPath);
                              },
                        child: const Text('Sign Up'),
                      ),
                    ],
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
