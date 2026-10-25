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
import 'signup_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  void _submit() {
    HapticFeedback.lightImpact();
    ref.read(signupNotifierProvider.notifier).submit(
          apiClient: ref.read(apiClientProvider),
          tokenStorage: ref.read(tokenStorageProvider),
          context: context,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final signupState = ref.watch(signupNotifierProvider);
    final signupNotifier = ref.read(signupNotifierProvider.notifier);

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
                        Icons.person_add_outlined,
                        size: 32,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Create an account',
                    style: AppTypography.headlineLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Find your accountability partner and achieve your goals.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Error Banner
                  if (signupState.errorMessage != null) ...[
                    ErrorBanner(
                      message: signupState.errorMessage,
                      onDismiss: signupNotifier.clearErrorMessage,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Full Name Field
                  AppTextField(
                    initialValue: signupState.name,
                    label: 'Full Name',
                    hint: 'Jane Doe',
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    error: signupState.nameError,
                    onChanged: signupNotifier.setName,
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Email Field
                  AppTextField(
                    initialValue: signupState.email,
                    label: 'Email',
                    hint: 'jane@example.com',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    error: signupState.emailError,
                    onChanged: signupNotifier.setEmail,
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Password Field
                  AppTextField(
                    initialValue: signupState.password,
                    label: 'Password',
                    hint: 'At least 8 characters',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    textInputAction: TextInputAction.next,
                    error: signupState.passwordError,
                    onChanged: signupNotifier.setPassword,
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Confirm Password Field
                  AppTextField(
                    initialValue: signupState.confirmPassword,
                    label: 'Confirm Password',
                    hint: 'Repeat password',
                    prefixIcon: Icons.lock_clock_outlined,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    error: signupState.confirmPasswordError,
                    onChanged: signupNotifier.setConfirmPassword,
                    onSubmitted: (_) {
                      if (!signupState.isLoading) {
                        _submit();
                      }
                    },
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Primary Submit Button
                  AppButton.primary(
                    label: 'Create Account',
                    isLoading: signupState.isLoading,
                    onPressed: signupState.isLoading ? null : _submit,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Link to Log In
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: signupState.isLoading
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                context.go(AppRoutes.loginPath);
                              },
                        child: const Text('Log In'),
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
