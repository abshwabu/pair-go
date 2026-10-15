import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../pods/pod_state.dart';
import 'streak_provider.dart';

/// Full screen interface for recording daily accountability check-in.
class CheckInsScreen extends ConsumerStatefulWidget {
  final String? podId;

  const CheckInsScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<CheckInsScreen> createState() => _CheckInsScreenState();
}

class _CheckInsScreenState extends ConsumerState<CheckInsScreen> {
  final TextEditingController _noteController = TextEditingController();
  String? _resolvedPodId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final activePod = ref.read(activePodDetailProvider).pod;
    final id = widget.podId ??
        ref.read(currentPodIdProvider) ??
        activePod?.id ??
        '';

    if (id.isEmpty) return;
    _resolvedPodId = id;

    final apiClient = ref.read(apiClientProvider);
    await ref.read(podStreakProvider(id).notifier).fetchStreak(apiClient);
  }

  Future<void> _handleCheckIn() async {
    if (_resolvedPodId == null) return;
    final apiClient = ref.read(apiClientProvider);
    final note = _noteController.text.trim();

    final success = await ref
        .read(podStreakProvider(_resolvedPodId!).notifier)
        .checkIn(apiClient, note: note.isNotEmpty ? note : null);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checked in successfully! Streak updated.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activePod = ref.watch(activePodDetailProvider).pod;

    final podId = _resolvedPodId ??
        widget.podId ??
        ref.watch(currentPodIdProvider) ??
        activePod?.id ??
        '';

    final streakState = ref.watch(podStreakProvider(podId));
    final streak = streakState.streak;
    final isCheckedIn = streak?.meCheckedInToday ?? false;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Daily Check-in'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (streakState.errorMessage != null) ...[
              ErrorBanner(message: streakState.errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],

            // Status Card
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isCheckedIn
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusLg,
              ),
              child: Column(
                children: [
                  Icon(
                    isCheckedIn
                        ? Icons.check_circle_rounded
                        : Icons.pending_actions_rounded,
                    size: 48,
                    color: isCheckedIn
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    isCheckedIn
                        ? 'You\'re Checked In for Today!'
                        : 'Log Today\'s Progress',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    isCheckedIn
                        ? 'Great job keeping your accountability promise. Your pod streak is burning bright.'
                        : 'Submit your check-in to keep the pod streak alive.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (!isCheckedIn) ...[
              Text(
                'Accomplishment Note (optional)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _noteController,
                maxLength: 500,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'What did you complete toward your goal today?',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.borderRadiusMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed:
                    streakState.isCheckingIn ? null : _handleCheckIn,
                child: streakState.isCheckingIn
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Confirm Daily Check-in'),
              ),
            ] else ...[
              FilledButton.tonal(
                onPressed: () {
                  context.push(
                    AppRoutes.streakDetailPath,
                    extra: podId,
                  );
                },
                child: const Text('View Streak Details & History'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
