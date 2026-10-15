import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';
import 'models/todo_model.dart';
import 'todos_provider.dart';
import 'widgets/add_edit_todo_modal.dart';

class TodoListScreen extends ConsumerStatefulWidget {
  final String? podId;

  const TodoListScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends ConsumerState<TodoListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final resolvedPodId = widget.podId ?? ref.read(currentPodIdProvider) ?? '';
    if (resolvedPodId.isNotEmpty) {
      final apiClient = ref.read(apiClientProvider);
      await ref
          .read(podTodosProvider(resolvedPodId).notifier)
          .fetchTodos(apiClient: apiClient, forceRefresh: forceRefresh);
    }
  }

  Widget _buildAssigneeBadge(
    BuildContext context,
    TodoModel todo,
    String currentUserId,
    String? partnerId,
    String? partnerName,
  ) {
    final theme = Theme.of(context);

    String label = 'Both';
    Color bgColor = theme.colorScheme.surfaceContainerHighest;
    Color fgColor = theme.colorScheme.onSurfaceVariant;
    IconData icon = Icons.group_rounded;

    if (todo.assignedTo == currentUserId) {
      label = 'Me';
      bgColor = theme.colorScheme.primaryContainer;
      fgColor = theme.colorScheme.onPrimaryContainer;
      icon = Icons.person_rounded;
    } else if (todo.assignedTo != null && todo.assignedTo == partnerId) {
      label = partnerName?.isNotEmpty == true ? partnerName! : 'Partner';
      bgColor = theme.colorScheme.secondaryContainer;
      fgColor = theme.colorScheme.onSecondaryContainer;
      icon = Icons.person_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoTile(
    BuildContext context,
    TodoModel todo,
    String resolvedPodId,
    String currentUserId,
    String? partnerId,
    String? partnerName,
  ) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Transform.scale(
          scale: 1.1,
          child: Checkbox(
            value: todo.isDone,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusSm,
            ),
            onChanged: (val) async {
              final apiClient = ref.read(apiClientProvider);
              final success = await ref
                  .read(podTodosProvider(resolvedPodId).notifier)
                  .toggleTodoOptimistic(
                    apiClient: apiClient,
                    todoId: todo.id,
                  );
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to update task. Changes reverted.'),
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
            decoration: todo.isDone ? TextDecoration.lineThrough : null,
            color: todo.isDone
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildAssigneeBadge(
                context,
                todo,
                currentUserId,
                partnerId,
                partnerName,
              ),
              if (todo.dueDate != null && todo.dueDate!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        todo.dueDate!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?.id ?? '';
    final activePod = ref.watch(activePodDetailProvider).pod;

    final resolvedPodId = widget.podId ??
        ref.watch(currentPodIdProvider) ??
        activePod?.id ??
        '';

    final partner = activePod?.partner(currentUserId);
    final partnerName = partner?.user.name ?? 'Partner';
    final partnerId = partner?.user.id;

    final todosState = ref.watch(podTodosProvider(resolvedPodId));
    final notifier = ref.read(podTodosProvider(resolvedPodId).notifier);

    final openList = todosState.openTodos(currentUserId, partnerId);
    final doneList = todosState.doneTodos(currentUserId, partnerId);

    final allTodos = todosState.todos;
    final mineCount =
        allTodos.where((t) => t.assignedTo == currentUserId).length;
    final partnerCount = partnerId != null
        ? allTodos.where((t) => t.assignedTo == partnerId).length
        : 0;
    final sharedCount = allTodos.where((t) => t.isShared).length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pod Tasks'),
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadData(forceRefresh: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Filter Chips Row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text('All (${allTodos.length})'),
                          selected: todosState.filter == TodoFilterType.all,
                          onSelected: (_) =>
                              notifier.setFilter(TodoFilterType.all),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ChoiceChip(
                          label: Text('Mine ($mineCount)'),
                          selected: todosState.filter == TodoFilterType.mine,
                          onSelected: (_) =>
                              notifier.setFilter(TodoFilterType.mine),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ChoiceChip(
                          label: Text(
                            partnerName.isNotEmpty
                                ? '$partnerName ($partnerCount)'
                                : "Partner's ($partnerCount)",
                          ),
                          selected:
                              todosState.filter == TodoFilterType.partner,
                          onSelected: (_) =>
                              notifier.setFilter(TodoFilterType.partner),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ChoiceChip(
                          label: Text('Shared ($sharedCount)'),
                          selected: todosState.filter == TodoFilterType.shared,
                          onSelected: (_) =>
                              notifier.setFilter(TodoFilterType.shared),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (todosState.errorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.xs,
                    ),
                    child: ErrorBanner(message: todosState.errorMessage!),
                  ),
                ),

              if (todosState.isLoading && allTodos.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                )
              else if (openList.isEmpty && doneList.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'No Tasks Found',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Create a task to build accountability with your partner.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton.icon(
                            onPressed: () {
                              showAddEditTodoModal(
                                context,
                                podId: resolvedPodId,
                                currentUserId: currentUserId,
                                partnerId: partnerId,
                                partnerName: partnerName,
                              );
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add First Task'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                // Open Section Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Open (${openList.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Open Items List
                if (openList.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.borderRadiusMd,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            'All open tasks completed! Tap + to add another.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final todo = openList[index];
                          return _buildTodoTile(
                            context,
                            todo,
                            resolvedPodId,
                            currentUserId,
                            partnerId,
                            partnerName,
                          );
                        },
                        childCount: openList.length,
                      ),
                    ),
                  ),

                // Done Section Header
                if (doneList.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.xs,
                      ),
                      child: Text(
                        'Completed (${doneList.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),

                  // Done Items List
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final todo = doneList[index];
                          return _buildTodoTile(
                            context,
                            todo,
                            resolvedPodId,
                            currentUserId,
                            partnerId,
                            partnerName,
                          );
                        },
                        childCount: doneList.length,
                      ),
                    ),
                  ),
                ],

                const SliverToBoxAdapter(
                  child: SizedBox(height: 80), // Padding for FAB
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showAddEditTodoModal(
            context,
            podId: resolvedPodId,
            currentUserId: currentUserId,
            partnerId: partnerId,
            partnerName: partnerName,
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Task'),
        tooltip: 'Add new task',
      ),
    );
  }
}
