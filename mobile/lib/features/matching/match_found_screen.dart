import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';

class MatchFoundScreen extends ConsumerStatefulWidget {
  final String? podId;

  const MatchFoundScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<MatchFoundScreen> createState() => _MatchFoundScreenState();
}

class _MatchFoundScreenState extends ConsumerState<MatchFoundScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiClient = ref.read(apiClientProvider);
      ref.read(activePodDetailProvider.notifier).loadPod(
            apiClient: apiClient,
            podId: widget.podId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podState = ref.watch(activePodDetailProvider);
    final currentUser = ref.watch(currentUserProvider);

    if (podState.isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    if (podState.errorMessage != null && podState.pod == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Match Details'),
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ErrorBanner(message: podState.errorMessage!),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () {
                    final apiClient = ref.read(apiClientProvider);
                    ref.read(activePodDetailProvider.notifier).loadPod(
                          apiClient: apiClient,
                          podId: widget.podId,
                          forceRefresh: true,
                        );
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pod = podState.pod;
    final partner = pod?.partner(currentUser?.id);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.md),

              // Celebration Icon Badge
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Center(
                  child: Icon(
                    Icons.celebration_rounded,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Celebratory Titles
              Text(
                "It's a Match!",
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Meet your new accountability partner',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              // Partner Card
              if (partner != null)
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.borderRadiusLg,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        // Avatar
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          backgroundImage: partner.user.avatarUrl != null &&
                                  partner.user.avatarUrl!.isNotEmpty
                              ? NetworkImage(partner.user.avatarUrl!)
                              : null,
                          child: partner.user.avatarUrl == null ||
                                  partner.user.avatarUrl!.isEmpty
                              ? Text(
                                  partner.user.name.isNotEmpty
                                      ? partner.user.name[0].toUpperCase()
                                      : 'P',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Partner Name
                        Text(
                          partner.user.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: AppSpacing.lg),

                        // Partner Goal Container
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: AppRadius.borderRadiusMd,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'THEIR GOAL',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                partner.goal.title,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.secondaryContainer,
                                      borderRadius:
                                          AppRadius.borderRadiusSm,
                                    ),
                                    child: Text(
                                      partner.goal.category.toUpperCase(),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: theme.colorScheme
                                            .onSecondaryContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.surfaceContainerHighest,
                                      borderRadius:
                                          AppRadius.borderRadiusSm,
                                    ),
                                    child: Text(
                                      '${partner.goal.pace} pace',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: AppSpacing.xxl),

              // "Let's start" button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final targetPodId = pod?.id ?? widget.podId;
                    context.go(
                      AppRoutes.podHomePath,
                      extra: targetPodId,
                    );
                  },
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text("Let's start"),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusMd,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
