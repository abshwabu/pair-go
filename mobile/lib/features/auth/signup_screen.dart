import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import 'signup_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signupState = ref.watch(signupNotifierProvider);
    final signupNotifier = ref.read(signupNotifierProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Create an account',
                    style: theme.textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Join Pair to achieve your goals together',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Error Banner
                  if (signupState.errorMessage != null)
                    ErrorBanner(
                      message: signupState.errorMessage,
                      onDismiss: signupNotifier.clearErrorMessage,
                    ),

                  // Name Field
                  TextFormField(
                    initialValue: signupState.name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'Jane Doe',
                      prefixIcon: const Icon(Icons.person_outline),
                      errorText: signupState.nameError,
                    ),
                    onChanged: signupNotifier.setName,
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Email Field
                  TextFormField(
                    initialValue: signupState.email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'jane@example.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      errorText: signupState.emailError,
                    ),
                    onChanged: signupNotifier.setEmail,
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Password Field
                  TextFormField(
                    initialValue: signupState.password,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'At least 8 characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      errorText: signupState.passwordError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    onChanged: signupNotifier.setPassword,
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Confirm Password Field
                  TextFormField(
                    initialValue: signupState.confirmPassword,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      hintText: 'Repeat password',
                      prefixIcon: const Icon(Icons.lock_clock_outlined),
                      errorText: signupState.confirmPasswordError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirm = !_obscureConfirm;
                          });
                        },
                      ),
                    ),
                    onChanged: signupNotifier.setConfirmPassword,
                    onFieldSubmitted: (_) {
                      if (!signupState.isLoading) {
                        signupNotifier.submit(
                          apiClient: ref.read(apiClientProvider),
                          tokenStorage: ref.read(tokenStorageProvider),
                          context: context,
                        );
                      }
                    },
                    enabled: !signupState.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Primary Submit Button
                  ElevatedButton(
                    onPressed: signupState.isLoading
                        ? null
                        : () => signupNotifier.submit(
                              apiClient: ref.read(apiClientProvider),
                              tokenStorage: ref.read(tokenStorageProvider),
                              context: context,
                            ),
                    child: signupState.isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Create Account'),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Link to Log In
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: signupState.isLoading
                            ? null
                            : () => context.go(AppRoutes.loginPath),
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
