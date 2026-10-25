import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_card.dart';
import 'matching_state_provider.dart';
import 'models/matching_state_model.dart';

class MatchPendingScreen extends ConsumerStatefulWidget {
  const MatchPendingScreen({super.key});

  @override
  ConsumerState<MatchPendingScreen> createState() => _MatchPendingScreenState();
}

class _MatchPendingScreenState extends ConsumerState<MatchPendingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _isCancelling = false;
  MatchingStateNotifier? _matchingNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    _opacityAnimation = Tween<double>(begin: 0.55, end: 0.95).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _matchingNotifier = ref.read(matchingStateProvider.notifier);
      _matchingNotifier?.startScreenPolling();
      _initCountdown();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _matchingNotifier?.stopScreenPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(matchingStateProvider.notifier).setAppLifecycleState(state);
  }

  void _initCountdown() {
    _updateRemaining();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final state = ref.read(matchingStateProvider).value;
    final expiresAt = state?.proposal?.expiresAt;
    if (expiresAt != null) {
      final now = DateTime.now().toUtc();
      final diff = expiresAt.difference(now);
      if (diff <= Duration.zero) {
        setState(() {
          _remaining = Duration.zero;
        });
        _countdownTimer?.cancel();
        ref.read(matchingStateProvider.notifier).refresh();
      } else {
        setState(() {
          _remaining = diff;
        });
      }
    }
  }

  String _formatCountdown(Duration d) {
    if (d <= Duration.zero) return 'Expired';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m ${seconds}s';
    }
  }

  String _formatTimezoneDiff(int partnerUtcOffsetHours) {
    final deviceOffsetHours = DateTime.now().timeZoneOffset.inMinutes / 60.0;
    final diff = (partnerUtcOffsetHours - deviceOffsetHours).round();

    if (diff == 0) {
      return 'Same timezone as you';
    } else if (diff > 0) {
      return '$diff ${diff == 1 ? 'hour' : 'hours'} ahead of you';
    } else {
      final absDiff = diff.abs();
      return '$absDiff ${absDiff == 1 ? 'hour' : 'hours'} behind you';
    }
  }

  Future<void> _handleCancel() async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Stop looking?'),
        content: const Text("You'll leave the matching queue."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Leave queue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isCancelling = true;
    });

    try {
      await ref.read(matchingStateProvider.notifier).cancel();
      if (!mounted) return;
      context.go(AppRoutes.goalCategoryPath);
    } catch (_) {
      if (!mounted) return;
      context.go(AppRoutes.goalCategoryPath);
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final matchAsync = ref.watch(matchingStateProvider);

    // Listen to polling updates for transitions
    ref.listen<AsyncValue<MatchingStateModel>>(matchingStateProvider,
        (prev, next) {
      final nextState = next.value;
      if (nextState == null) return;

      if (nextState.isMatched) {
        context.go(AppRoutes.matchConfirmedPath, extra: nextState.podId);
      } else if (nextState.isSearching) {
        final partnerName =
            prev?.value?.proposal?.partner.name ?? 'Your partner';
        final firstName = partnerName.split(' ').first;
        ref.read(matchingStateProvider.notifier).setRejectionBanner(
              "$firstName wasn't able to confirm. We're finding you someone new.",
            );
        context.go(AppRoutes.findingMatchPath);
      } else if (nextState.isNone) {
        context.go(AppRoutes.goalCategoryPath);
      }
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: matchAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: TextButton(
              onPressed: () =>
                  ref.read(matchingStateProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ),
          data: (state) {
            final proposal = state.proposal;
            final partner = proposal?.partner;
            final partnerGoal = proposal?.partnerGoal;
            final fullName = partner?.name ?? 'your partner';
            final firstName = fullName.split(' ').first;

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 1),

                  // Calm Breathing Animation
                  Center(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primaryContainer
                                  .withValues(alpha: _opacityAnimation.value * 0.4),
                              border: Border.all(
                                color: colorScheme.primary
                                    .withValues(alpha: _opacityAnimation.value * 0.7),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.hourglass_top_rounded,
                                size: 52,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // Headline with partner's first name
                  Text(
                    'Waiting for $firstName to confirm',
                    style: AppTypography.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Live Countdown Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.borderRadiusFull,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Expires in ${_formatCountdown(_remaining)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Compact Partner Mini-Card
                  if (partner != null && partnerGoal != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            AppAvatar(
                              size: AppAvatarSize.md,
                              imageUrl: partner.avatarUrl,
                              name: partner.name,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    partner.name,
                                    style: AppTypography.titleMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    partnerGoal.title,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimezoneDiff(
                                        partner.utcOffsetHours),
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const Spacer(flex: 2),

                  // Cancel text button
                  TextButton(
                    onPressed: _isCancelling ? null : _handleCancel,
                    child: _isCancelling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Cancel',
                            style: AppTypography.labelLarge.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
