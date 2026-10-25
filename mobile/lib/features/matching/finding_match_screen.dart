import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/error_banner.dart';
import 'finding_match_provider.dart';
import 'matching_state_provider.dart';
import 'models/matching_state_model.dart';

class FindingMatchScreen extends ConsumerStatefulWidget {
  const FindingMatchScreen({super.key});

  @override
  ConsumerState<FindingMatchScreen> createState() => _FindingMatchScreenState();
}

class _FindingMatchScreenState extends ConsumerState<FindingMatchScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseScaleAnimation;
  late Animation<double> _pulseOpacityAnimation;

  FindingMatchNotifier? _notifier;
  MatchingStateNotifier? _matchingNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseScaleAnimation = Tween<double>(begin: 0.94, end: 1.14).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    _pulseOpacityAnimation = Tween<double>(begin: 0.45, end: 0.9).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _matchingNotifier = ref.read(matchingStateProvider.notifier);
      _matchingNotifier?.startScreenPolling();
      _notifier = ref.read(findingMatchNotifierProvider.notifier);
      final apiClient = ref.read(apiClientProvider);
      _notifier?.startMatching(apiClient: apiClient);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _notifier?.stopPolling();
    _matchingNotifier?.stopScreenPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(matchingStateProvider.notifier).setAppLifecycleState(state);
  }

  Future<void> _handleCancelSearch() async {
    HapticFeedback.lightImpact();
    final apiClient = ref.read(apiClientProvider);
    try {
      await ref
          .read(findingMatchNotifierProvider.notifier)
          .cancelSearch(apiClient: apiClient);
    } catch (_) {}

    try {
      await ref.read(matchingStateProvider.notifier).cancel();
    } catch (_) {}

    if (mounted) {
      context.go(AppRoutes.matchingPrefsPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;
    final legacyMatchState = ref.watch(findingMatchNotifierProvider);
    final unifiedAsync = ref.watch(matchingStateProvider);
    final unifiedState = unifiedAsync.value;

    // Listen to unified matching state changes for clean declarative navigation
    ref.listen<AsyncValue<MatchingStateModel>>(matchingStateProvider,
        (previous, next) {
      final nextState = next.value;
      if (nextState == null) return;

      if (nextState.isProposed) {
        navigateForMatchingState(context, nextState, inMatchingFlow: true);
      } else if (nextState.isMatched) {
        context.go(AppRoutes.matchConfirmedPath, extra: nextState.podId);
      } else if (nextState.isNone && previous?.value?.isSearching == true) {
        context.go(AppRoutes.goalCategoryPath);
      }
    });

    final currentStatusMessage =
        FindingMatchNotifier.statusMessages[legacyMatchState.statusTextIndex];
    final bannerMessage = unifiedState?.rejectionBannerMessage;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            children: [
              // Top Dismissible Rejection/Timeout Banner
              if (bannerMessage != null && bannerMessage.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: AppRadius.borderRadiusMd,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          bannerMessage,
                          style: AppTypography.bodySmall.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          ref
                              .read(matchingStateProvider.notifier)
                              .clearRejectionBanner();
                        },
                      ),
                    ],
                  ),
                ),

              const Spacer(flex: 1),

              // Animated Radar Orb Visualizer
              Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = _pulseScaleAnimation.value;
                    final opacity = _pulseOpacityAnimation.value;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer Radar Ring
                        Transform.scale(
                          scale: scale * 1.18,
                          child: Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tokens.flame.withValues(alpha: opacity * 0.12),
                              border: Border.all(
                                color: tokens.flame.withValues(alpha: opacity * 0.35),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        // Middle Pulsing Ring
                        Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 135,
                            height: 135,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primaryContainer
                                  .withValues(alpha: opacity * 0.45),
                              border: Border.all(
                                color: colorScheme.primary
                                  .withValues(alpha: opacity * 0.6),
                                width: 2.0,
                              ),
                            ),
                          ),
                        ),
                        // Inner Core Container
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.3),
                                blurRadius: 18,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.people_alt_rounded,
                            size: 46,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // Title
              Text(
                'Finding your Pair',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.sm),

              // Rotating Status Text
              SizedBox(
                height: 48,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Text(
                    currentStatusMessage,
                    key: ValueKey<int>(legacyMatchState.statusTextIndex),
                    style: AppTypography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              if (legacyMatchState.errorMessage != null)
                ErrorBanner(message: legacyMatchState.errorMessage!),

              const Spacer(flex: 2),

              // Cancel Search Button
              AppButton.secondary(
                label: 'Cancel Search',
                isLoading: legacyMatchState.isCancelling,
                leadingIcon: Icons.close_rounded,
                onPressed: legacyMatchState.isCancelling
                    ? null
                    : _handleCancelSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
