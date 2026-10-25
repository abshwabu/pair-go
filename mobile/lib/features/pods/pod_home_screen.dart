import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_shimmer.dart';
import '../../core/widgets/error_banner.dart';
import '../auth/auth_state.dart';
import '../todos/todos_provider.dart';
import '../todos/widgets/add_edit_todo_modal.dart';
import '../checkins/streak_provider.dart';
import '../checkins/widgets/daily_checkin_card.dart';
import '../checkins/widgets/streak_badge.dart';
import 'models/pod_model.dart';
import 'pod_state.dart';

class PodHomeScreen extends ConsumerStatefulWidget {
  final String? podId;

  const PodHomeScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<PodHomeScreen> createState() => _PodHomeScreenState();
}

class _PodHomeScreenState extends ConsumerState<PodHomeScreen> {
  bool _isRejecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _handleRejectSuggestion(
    String targetPodId,
    PodMemberDetail? partner,
  ) async {
    if (targetPodId.isEmpty) return;

    bool blockPartner = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Reject Suggestion?'),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusCard,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to decline this accountability partner suggestion with ${partner?.user.name.isNotEmpty == true ? partner!.user.name : "this partner"}?',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This pod will be dissolved and you can search for a different partner.',
                style: AppTypography.bodySmall.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              if (partner != null && partner.user.id.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: blockPartner,
                  onChanged: (val) {
                    setDialogState(() {
                      blockPartner = val ?? false;
                    });
                  },
                  title: const Text(
                    "Don't suggest this user again (block)",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Keep Match'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Reject Suggestion'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isRejecting = true;
    });

    final apiClient = ref.read(apiClientProvider);

    try {
      if (blockPartner && partner != null && partner.user.id.isNotEmpty) {
        await apiClient.post<Map<String, dynamic>>(
          '/blocks',
          data: {'blocked_user_id': partner.user.id},
        );
      } else {
        await apiClient.post<Map<String, dynamic>>('/pods/$targetPodId/leave');
      }

      ref.read(activePodDetailProvider.notifier).clearPod();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Match suggestion rejected. Let’s find a new partner!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppRoutes.goalCategoryPath);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isRejecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRejecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to reject match suggestion.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _loadData() async {
    final apiClient = ref.read(apiClientProvider);
    final pod = await ref.read(activePodDetailProvider.notifier).loadPod(
          apiClient: apiClient,
          podId: widget.podId,
        );

    if (pod != null && mounted) {
      ref
          .read(podTodosProvider(pod.id).notifier)
          .fetchTodos(apiClient: apiClient);
      ref
          .read(podStreakProvider(pod.id).notifier)
          .fetchStreak(apiClient);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final podState = ref.watch(activePodDetailProvider);
    final currentUser = ref.watch(currentUserProvider);

    if (podState.isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Pod Home'),
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppShimmer.card(height: 180),
              const SizedBox(height: AppSpacing.lg),
              AppShimmer.card(height: 80),
              const SizedBox(height: AppSpacing.lg),
              AppShimmer.box(width: 140, height: 24),
              const SizedBox(height: AppSpacing.sm),
              AppShimmer.card(height: 64),
              const SizedBox(height: AppSpacing.sm),
              AppShimmer.card(height: 64),
            ],
          ),
        ),
      );
    }

    if (podState.errorMessage != null && podState.pod == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Pod Home'),
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ErrorBanner(message: podState.errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _loadData,
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.goalCategoryPath),
                    child: const Text('Find a New Match'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final pod = podState.pod;
    final partner = pod?.partner(currentUser?.id);
    final myMembership = pod?.myMembership(currentUser?.id);
    final resolvedPodId = pod?.id ?? widget.podId ?? '';

    // Watch single podTodosProvider so top 3 preview stays synchronized
    final todosState = ref.watch(podTodosProvider(resolvedPodId));
    final todosPreview = todosState.top3OpenTodos;
    final isLoadingTodos = todosState.isLoading;

    final categoryName = pod != null && pod.goalCategory.isNotEmpty
        ? '${pod.goalCategory[0].toUpperCase()}${pod.goalCategory.substring(1)} Pod'
        : 'Accountability Pod';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(categoryName),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pod Settings',
            onPressed: () {
              context.go(
                AppRoutes.podSettingsPath,
                extra: resolvedPodId,
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final apiClient = ref.read(apiClientProvider);
          await ref.read(activePodDetailProvider.notifier).loadPod(
                apiClient: apiClient,
                podId: resolvedPodId,
                forceRefresh: true,
              );
          if (mounted && resolvedPodId.isNotEmpty) {
            await Future.wait([
              ref
                  .read(podTodosProvider(resolvedPodId).notifier)
                  .fetchTodos(apiClient: apiClient, forceRefresh: true),
              ref
                  .read(podStreakProvider(resolvedPodId).notifier)
                  .fetchStreak(apiClient, forceRefresh: true),
            ]);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Daily Check-in prompt card (dismissible, shown if me_checked_in_today is false)
              DailyCheckinCard(
                podId: resolvedPodId,
                partnerName: partner?.user.name,
              ),

              // 1. Partner Info & Streak Badge Header Card with overlapped avatars
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Overlapped Avatars Stack
                        SizedBox(
                          width: 60,
                          height: 48,
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                top: 2,
                                child: AppAvatar(
                                  imageUrl: currentUser?.avatarUrl,
                                  name: currentUser?.name ?? 'You',
                                  size: AppAvatarSize.md,
                                ),
                              ),
                              Positioned(
                                left: 18,
                                top: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: AppAvatar(
                                    imageUrl: partner?.user.avatarUrl,
                                    name: partner?.user.name ?? 'Partner',
                                    size: AppAvatarSize.md,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                partner?.user.name ?? 'Partner',
                                style: AppTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Accountability Partner',
                                style: AppTypography.bodySmall.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Streak Badge (embedded widget, tapping routes to streak-detail)
                        StreakBadge(
                          podId: resolvedPodId,
                          fallbackCurrentStreak: pod?.streak.currentStreak,
                          fallbackBestStreak: pod?.streak.bestStreak,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.md),
                    const Divider(),
                    const SizedBox(height: AppSpacing.sm),

                    // Goals comparison
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: AppRadius.borderRadiusMd,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'THEIR GOAL',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  partner?.goal.title ?? 'No goal details',
                                  style: AppTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: AppRadius.borderRadiusMd,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOUR GOAL',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: tokens.flame,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  myMembership?.goal.title ?? 'Your goal',
                                  style: AppTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _isRejecting
                              ? null
                              : () => _handleRejectSuggestion(
                                    resolvedPodId,
                                    partner,
                                  ),
                          icon: Icon(
                            Icons.person_remove_outlined,
                            size: 16,
                            color: theme.colorScheme.error,
                          ),
                          label: Text(
                            'Reject Suggestion / Change Partner',
                            style: AppTypography.labelMedium.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // 2. Daily Check-in Quick Action Card
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: tokens.flameBackground,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tokens.flame.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.fact_check_rounded,
                        color: tokens.flame,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Check-in',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Keep your streak alive by checking in today.',
                            style: AppTypography.bodySmall.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.borderRadiusMd,
                        ),
                      ),
                      onPressed: () {
                        context.go(
                          AppRoutes.checkinPath,
                          extra: resolvedPodId,
                        );
                      },
                      child: const Text('Check In'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // 3. Open Todos Preview Section (Wired to podTodosProvider)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Open Todos',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      context.go(
                        AppRoutes.todoListPath,
                        extra: resolvedPodId,
                      );
                    },
                    child: const Text('View all'),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xs),

              if (isLoadingTodos && todosState.todos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: [
                      AppShimmer.card(height: 60),
                      const SizedBox(height: AppSpacing.xs),
                      AppShimmer.card(height: 60),
                    ],
                  ),
                )
              else if (todosPreview.isEmpty)
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 28,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'No open tasks yet. Create one to stay accountable!',
                          style: AppTypography.bodyMedium.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          showAddEditTodoModal(
                            context,
                            podId: resolvedPodId,
                            currentUserId: currentUser?.id ?? '',
                            partnerId: partner?.user.id,
                            partnerName: partner?.user.name,
                          );
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                )
              else
                ...todosPreview.map((todo) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.borderRadiusCard,
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: Transform.scale(
                        scale: 1.15,
                        child: Checkbox(
                          value: todo.isDone,
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.borderRadiusSm,
                          ),
                          onChanged: (val) async {
                            final apiClient = ref.read(apiClientProvider);
                            final ok = await ref
                                .read(podTodosProvider(resolvedPodId).notifier)
                                .toggleTodoOptimistic(
                                  apiClient: apiClient,
                                  todoId: todo.id,
                                );
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to update task.'),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      title: Text(
                        todo.title,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration:
                              todo.isDone ? TextDecoration.lineThrough : null,
                          color: todo.isDone
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: todo.dueDate != null && todo.dueDate!.isNotEmpty
                          ? Text(
                              'Due: ${todo.dueDate}',
                              style: AppTypography.bodySmall.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                      ),
                      onTap: () {
                        context.go(
                          AppRoutes.todoDetailPath,
                          extra: {'todo': todo, 'pod_id': resolvedPodId},
                        );
                      },
                    ),
                  );
                }),

              const SizedBox(height: 80), // Padding for FAB
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.go(
            AppRoutes.chatPath,
            extra: resolvedPodId,
          );
        },
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: const Text('Chat'),
        tooltip: 'Open Chat',
      ),
    );
  }
}
