import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/status_chip.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';
import 'models/todo_model.dart';
import 'todos_provider.dart';
import 'widgets/add_edit_todo_modal.dart';

class TodoDetailScreen extends ConsumerStatefulWidget {
  final TodoModel? todo;
  final String? todoId;
  final String? podId;

  const TodoDetailScreen({
    super.key,
    this.todo,
    this.todoId,
    this.podId,
  });

  @override
  ConsumerState<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends ConsumerState<TodoDetailScreen> {
  String? _errorMessage;
  bool _isDeleting = false;

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _handleDelete(String resolvedPodId, String todoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusCard,
          ),
          title: const Text('Delete Task?'),
          content: Text(
            'Are you sure you want to delete this task? This action cannot be undone.',
            style: AppTypography.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    final apiClient = ref.read(apiClientProvider);
    final success = await ref
        .read(podTodosProvider(resolvedPodId).notifier)
        .deleteTodo(apiClient: apiClient, todoId: todoId);

    if (mounted) {
      if (success) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.todoListPath, extra: resolvedPodId);
        }
      } else {
        setState(() {
          _isDeleting = false;
          _errorMessage = 'Failed to delete task. You might not have permission.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final currentUser = ref.watch(currentUserProvider);
    final activePod = ref.watch(activePodDetailProvider).pod;

    final resolvedPodId = widget.todo?.podId ??
        widget.podId ??
        ref.watch(currentPodIdProvider) ??
        '';

    final todosState = ref.watch(podTodosProvider(resolvedPodId));
    final targetId = widget.todo?.id ?? widget.todoId ?? '';

    // Find the latest todo in state (or fallback to passed widget.todo)
    final todo = todosState.todos.firstWhere(
      (t) => t.id == targetId,
      orElse: () => widget.todo ??
          TodoModel(
            id: targetId,
            podId: resolvedPodId,
            createdBy: currentUser?.id ?? '',
            title: 'Task Details',
          ),
    );

    final partner = activePod?.partner(currentUser?.id);
    final partnerName = partner?.user.name ?? 'Partner';
    final partnerId = partner?.user.id;

    String assigneeText = 'Shared (Both)';
    IconData assigneeIcon = Icons.group_rounded;
    if (todo.assignedTo == currentUser?.id) {
      assigneeText = 'Assigned to Me';
      assigneeIcon = Icons.person_rounded;
    } else if (todo.assignedTo != null && todo.assignedTo == partnerId) {
      assigneeText = 'Assigned to $partnerName';
      assigneeIcon = Icons.person_outline_rounded;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Task Details'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Task',
            onPressed: () {
              showAddEditTodoModal(
                context,
                podId: resolvedPodId,
                existingTodo: todo,
                currentUserId: currentUser?.id ?? '',
                partnerId: partnerId,
                partnerName: partnerName,
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: theme.colorScheme.error,
            ),
            tooltip: 'Delete Task',
            onPressed: _isDeleting
                ? null
                : () => _handleDelete(resolvedPodId, todo.id),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null) ...[
                ErrorBanner(message: _errorMessage!),
                const SizedBox(height: AppSpacing.md),
              ],

              if (_isDeleting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),

              // Title and Completion Status Card
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.scale(
                          scale: 1.25,
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
                                    content: Text('Failed to update task. Reverted.'),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                todo.title,
                                style: AppTypography.headlineSmall.copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: todo.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: todo.isDone
                                      ? theme.colorScheme.onSurfaceVariant
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              todo.isDone
                                  ? const StatusChip.success(label: 'Completed')
                                  : StatusChip.warning(
                                      label: 'In Progress',
                                      icon: Icons.hourglass_top_rounded,
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Assignee & Due Date Meta Info
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusCard,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          assigneeIcon,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Assignee',
                        style: AppTypography.labelSmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        assigneeText,
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tokens.flameBackground,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.calendar_today_rounded,
                          color: tokens.flame,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Due Date',
                        style: AppTypography.labelSmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        todo.dueDate != null && todo.dueDate!.isNotEmpty
                            ? todo.dueDate!
                            : 'No due date',
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Notes Section
              Text(
                'NOTES',
                style: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusCard,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  todo.notes != null && todo.notes!.trim().isNotEmpty
                      ? todo.notes!
                      : 'No notes provided for this task.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: todo.notes != null && todo.notes!.trim().isNotEmpty
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontStyle: todo.notes == null || todo.notes!.trim().isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Timestamps Info
              if (todo.createdAt != null || todo.completedAt != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (todo.createdAt != null)
                        Text(
                          'Created on ${_formatDate(todo.createdAt)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (todo.completedAt != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Completed on ${_formatDate(todo.completedAt)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: AppSpacing.xxl),

              // Quick Toggle Completion Action Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
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
                          content: Text('Failed to update task. Reverted.'),
                        ),
                      );
                    }
                  },
                  icon: Icon(
                    todo.isDone
                        ? Icons.remove_done_rounded
                        : Icons.check_circle_outline_rounded,
                  ),
                  label: Text(
                    todo.isDone
                        ? 'Mark as Incomplete'
                        : 'Mark as Completed',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: const RoundedRectangleBorder(
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
