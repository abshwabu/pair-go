import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import 'finding_match_provider.dart';

class FindingMatchScreen extends ConsumerStatefulWidget {
  const FindingMatchScreen({super.key});

  @override
  ConsumerState<FindingMatchScreen> createState() => _FindingMatchScreenState();
}

class _FindingMatchScreenState extends ConsumerState<FindingMatchScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScaleAnimation;
  late Animation<double> _pulseOpacityAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseScaleAnimation = Tween<double>(begin: 0.94, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseOpacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier = ref.read(findingMatchNotifierProvider.notifier);
      final apiClient = ref.read(apiClientProvider);
      _notifier?.startMatching(apiClient: apiClient);
    });
  }

  FindingMatchNotifier? _notifier;

  @override
  void dispose() {
    _pulseController.dispose();
    _notifier?.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchState = ref.watch(findingMatchNotifierProvider);
    final apiClient = ref.read(apiClientProvider);

    // Listen to matching state changes for clean declarative navigation
    ref.listen<FindingMatchState>(findingMatchNotifierProvider, (previous, next) {
      if (next.matchedPodId != null && next.matchedPodId != previous?.matchedPodId) {
        context.go(AppRoutes.matchFoundPath, extra: next.matchedPodId);
      } else if (next.shouldRouteToGoalCategory &&
          previous?.shouldRouteToGoalCategory != true) {
        context.go(AppRoutes.goalCategoryPath);
      }
    });

    final currentStatusMessage =
        FindingMatchNotifier.statusMessages[matchState.statusTextIndex];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // Animated Pulsing Matching Visualizer
              Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseScaleAnimation.value,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: _pulseOpacityAnimation.value * 0.45,
                          ),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: _pulseOpacityAnimation.value * 0.6,
                            ),
                            width: 2.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primaryContainer,
                            ),
                            child: Icon(
                              Icons.people_alt_rounded,
                              size: 52,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // Title
              Text(
                'Finding your Pair',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.md),

              // Rotating Status Text
              SizedBox(
                height: 48,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    currentStatusMessage,
                    key: ValueKey<int>(matchState.statusTextIndex),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              if (matchState.errorMessage != null)
                ErrorBanner(message: matchState.errorMessage!),

              const Spacer(flex: 2),

              // Cancel Search Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: matchState.isCancelling
                      ? null
                      : () async {
                          await ref
                              .read(findingMatchNotifierProvider.notifier)
                              .cancelSearch(apiClient: apiClient);
                          if (context.mounted) {
                            context.go(AppRoutes.matchingPrefsPath);
                          }
                        },
                  icon: matchState.isCancelling
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.close_rounded),
                  label: Text(
                    matchState.isCancelling
                        ? 'Cancelling...'
                        : 'Cancel Search',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusMd,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
