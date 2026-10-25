import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';

class MatchConfirmedScreen extends ConsumerStatefulWidget {
  final String? podId;

  const MatchConfirmedScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<MatchConfirmedScreen> createState() =>
      _MatchConfirmedScreenState();
}

class _MatchConfirmedScreenState extends ConsumerState<MatchConfirmedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _celebrationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(
        parent: _celebrationController,
        curve: Curves.easeInOutBack,
      ),
    );

    _rotationAnimation = Tween<double>(begin: -0.05, end: 0.05).animate(
      CurvedAnimation(
        parent: _celebrationController,
        curve: Curves.easeInOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiClient = ref.read(apiClientProvider);
      ref.read(activePodDetailProvider.notifier).loadPod(
            apiClient: apiClient,
            podId: widget.podId,
          );
    });
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podState = ref.watch(activePodDetailProvider);
    final currentUser = ref.watch(currentUserProvider);
    final pod = podState.pod;

    final targetPodId = widget.podId ?? pod?.id;
    final partner = pod?.partner(currentUser?.id);
    final me = pod?.myMembership(currentUser?.id);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),

              // Simple Custom Celebration Animation
              Center(
                child: AnimatedBuilder(
                  animation: _celebrationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _rotationAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primaryContainer,
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.25),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.celebration_rounded,
                              size: 52,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // Title & Subtitle
              Text(
                "You're paired!",
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Meet your accountability partner and crush your goals together.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xxl),

              // Both Avatars and Both Goals
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusLg,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Current User Avatar
                          Column(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                backgroundImage: currentUser?.avatarUrl !=
                                            null &&
                                        currentUser!.avatarUrl!.isNotEmpty
                                    ? NetworkImage(currentUser.avatarUrl!)
                                    : null,
                                child: currentUser?.avatarUrl == null ||
                                        currentUser!.avatarUrl!.isEmpty
                                    ? Text(
                                        currentUser?.name.isNotEmpty == true
                                            ? currentUser!.name[0].toUpperCase()
                                            : 'U',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: theme
                                              .colorScheme.onPrimaryContainer,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                currentUser?.name ?? 'You',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),

                          // Partnership Icon
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.xs),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.surface,
                            ),
                            child: Icon(
                              Icons.handshake_rounded,
                              size: 28,
                              color: theme.colorScheme.primary,
                            ),
                          ),

                          // Partner Avatar
                          Column(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                backgroundImage: partner?.user.avatarUrl !=
                                            null &&
                                        partner!.user.avatarUrl!.isNotEmpty
                                    ? NetworkImage(partner.user.avatarUrl!)
                                    : null,
                                child: partner?.user.avatarUrl == null ||
                                        partner!.user.avatarUrl!.isEmpty
                                    ? Text(
                                        partner?.user.name.isNotEmpty == true
                                            ? partner!.user.name[0]
                                                .toUpperCase()
                                            : 'P',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme
                                              .onSecondaryContainer,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                partner?.user.name ?? 'Partner',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.md),

                      // Goals comparison
                      if (me?.goal != null || partner?.goal != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'YOUR GOAL',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    me?.goal.title ?? 'Your goal',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 36,
                              width: 1,
                              color: theme.dividerColor,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'PARTNER GOAL',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.secondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    partner?.goal.title ?? 'Partner goal',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // Single Button: "Go to your pod"
              FilledButton(
                onPressed: () {
                  context.go(AppRoutes.podHomePath, extra: targetPodId);
                },
                child: const Text('Go to your pod'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
