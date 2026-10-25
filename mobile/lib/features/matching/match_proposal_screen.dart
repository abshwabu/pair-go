import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/error_banner.dart';
import 'matching_state_provider.dart';

class MatchProposalScreen extends ConsumerStatefulWidget {
  const MatchProposalScreen({super.key});

  @override
  ConsumerState<MatchProposalScreen> createState() =>
      _MatchProposalScreenState();
}

class _MatchProposalScreenState extends ConsumerState<MatchProposalScreen>
    with WidgetsBindingObserver {
  bool _isSubmitting = false;
  String? _errorMessage;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  MatchingStateNotifier? _matchingNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

  Future<void> _handleAccept(String proposalId) async {
    HapticFeedback.lightImpact();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final updatedState =
          await ref.read(matchingStateProvider.notifier).accept(proposalId);
      if (!mounted) return;

      if (updatedState.isMatched) {
        context.go(AppRoutes.matchConfirmedPath, extra: updatedState.podId);
      } else {
        context.go(AppRoutes.matchPendingPath);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'proposal_closed' || e.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This match is no longer available.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        final latest =
            await ref.read(matchingStateProvider.notifier).refresh();
        if (mounted) {
          navigateForMatchingState(context, latest, inMatchingFlow: true);
        }
      } else {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to accept match. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handlePass(String proposalId) async {
    HapticFeedback.lightImpact();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (bottomSheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pass on this match?',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(bottomSheetCtx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "We'll keep looking for someone else.",
                style: AppTypography.bodyMedium.copyWith(
                  color: Theme.of(bottomSheetCtx)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(bottomSheetCtx).pop(false),
                      child: const Text('Keep Match'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(bottomSheetCtx).colorScheme.error,
                        foregroundColor:
                            Theme.of(bottomSheetCtx).colorScheme.onError,
                      ),
                      onPressed: () => Navigator.of(bottomSheetCtx).pop(true),
                      child: const Text('Pass'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(matchingStateProvider.notifier).reject(proposalId);
      if (!mounted) return;
      context.go(AppRoutes.findingMatchPath);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'proposal_closed' || e.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This match is no longer available.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        final latest =
            await ref.read(matchingStateProvider.notifier).refresh();
        if (mounted) {
          navigateForMatchingState(context, latest, inMatchingFlow: true);
        }
      } else {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to pass on match. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final matchAsync = ref.watch(matchingStateProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Match Proposal'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: SafeArea(
        child: matchAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ErrorBanner(message: err.toString()),
                  const SizedBox(height: AppSpacing.md),
                  AppButton.primary(
                    label: 'Retry',
                    isFullWidth: false,
                    onPressed: () =>
                        ref.read(matchingStateProvider.notifier).refresh(),
                  ),
                ],
              ),
            ),
          ),
          data: (state) {
            final proposal = state.proposal;
            if (proposal == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('No match proposal available.'),
                      const SizedBox(height: AppSpacing.md),
                      AppButton.primary(
                        label: 'Continue',
                        isFullWidth: false,
                        onPressed: () => navigateForMatchingState(
                          context,
                          state,
                          inMatchingFlow: true,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final partner = proposal.partner;
            final partnerGoal = proposal.partnerGoal;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage != null) ...[
                        ErrorBanner(message: _errorMessage!),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // Live Expiry Banner
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.6),
                          borderRadius: AppRadius.borderRadiusSm,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Respond within ${_formatCountdown(_remaining)}',
                              style: AppTypography.labelLarge.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Prominent Partner Card
                      AppCard(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          children: [
                            AppAvatar(
                              size: AppAvatarSize.xl,
                              imageUrl: partner.avatarUrl,
                              name: partner.name,
                              hasRing: true,
                              ringColor: colorScheme.primary,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              partner.name,
                              style: AppTypography.headlineSmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              partnerGoal.title,
                              style: AppTypography.titleMedium.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Category and Pace Chips
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                Chip(
                                  avatar: const Icon(Icons.flag_outlined,
                                      size: 16),
                                  label: Text(
                                    partnerGoal.category.toUpperCase(),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  avatar: const Icon(Icons.speed_rounded,
                                      size: 16),
                                  label: Text(
                                    partnerGoal.pace.toUpperCase(),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.md),
                            const Divider(),
                            const SizedBox(height: AppSpacing.sm),

                            // Timezone Difference Info
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.public_rounded,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  _formatTimezoneDiff(partner.utcOffsetHours),
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // Actions
                      AppButton.primary(
                        label: "Let's go",
                        isLoading: _isSubmitting,
                        onPressed: _isSubmitting
                            ? null
                            : () => _handleAccept(proposal.id),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton.secondary(
                        label: 'Pass',
                        isLoading: _isSubmitting,
                        onPressed: _isSubmitting
                            ? null
                            : () => _handlePass(proposal.id),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
