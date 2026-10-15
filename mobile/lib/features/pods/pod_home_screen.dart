import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../auth/auth_state.dart';
import '../todos/todos_provider.dart';
import '../todos/widgets/add_edit_todo_modal.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
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
    }
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
          title: const Text('Pod Home'),
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
            await ref
                .read(podTodosProvider(resolvedPodId).notifier)
                .fetchTodos(apiClient: apiClient, forceRefresh: true);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Partner Info & Streak Badge Header Card
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
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            backgroundImage: partner?.user.avatarUrl != null &&
                                    partner!.user.avatarUrl!.isNotEmpty
                                ? NetworkImage(partner.user.avatarUrl!)
                                : null,
                            child: partner?.user.avatarUrl == null ||
                                    partner!.user.avatarUrl!.isEmpty
                                ? Text(
                                    partner?.user.name.isNotEmpty == true
                                        ? partner!.user.name[0].toUpperCase()
                                        : 'P',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  partner?.user.name ?? 'Partner',
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Accountability Partner',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Streak Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: AppRadius.borderRadiusLg,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_fire_department_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${pod?.streak.currentStreak ?? 0} streak',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                    Text(
                                      'Best: ${pod?.streak.bestStreak ?? 0}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: theme.colorScheme
                                            .onPrimaryContainer
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'THEIR GOAL',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  partner?.goal.title ?? 'No goal details',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOUR GOAL',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  myMembership?.goal.title ?? 'Your goal',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // 2. Daily Check-in Card (Placeholder / Quick action)
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusLg,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fact_check_rounded,
                          color: theme.colorScheme.onSecondaryContainer,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Daily Check-in',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Keep your streak alive by checking in today.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.tonal(
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
              ),

              const SizedBox(height: AppSpacing.xl),

              // 3. Open Todos Preview Section (Wired to podTodosProvider)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Open Todos',
                    style: theme.textTheme.titleMedium?.copyWith(
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
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                )
              else if (todosPreview.isEmpty)
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                  child: Padding(
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
                            style: theme.textTheme.bodyMedium?.copyWith(
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
                  ),
                )
              else
                ...todosPreview.map((todo) {
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusMd,
                    ),
                    child: ListTile(
                      leading: Transform.scale(
                        scale: 1.1,
                        child: Checkbox(
                          value: todo.isDone,
                          shape: RoundedRectangleBorder(
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
                        style: theme.textTheme.bodyMedium?.copyWith(
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
                              style: theme.textTheme.bodySmall?.copyWith(
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
