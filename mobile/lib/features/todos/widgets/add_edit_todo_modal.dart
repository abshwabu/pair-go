import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../models/todo_model.dart';
import '../todos_provider.dart';

Future<TodoModel?> showAddEditTodoModal(
  BuildContext context, {
  required String podId,
  TodoModel? existingTodo,
  required String currentUserId,
  String? partnerId,
  String? partnerName,
}) {
  return showModalBottomSheet<TodoModel?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (modalContext) => AddEditTodoModal(
      podId: podId,
      existingTodo: existingTodo,
      currentUserId: currentUserId,
      partnerId: partnerId,
      partnerName: partnerName,
    ),
  );
}

class AddEditTodoModal extends ConsumerStatefulWidget {
  final String podId;
  final TodoModel? existingTodo;
  final String currentUserId;
  final String? partnerId;
  final String? partnerName;

  const AddEditTodoModal({
    super.key,
    required this.podId,
    this.existingTodo,
    required this.currentUserId,
    this.partnerId,
    this.partnerName,
  });

  @override
  ConsumerState<AddEditTodoModal> createState() => _AddEditTodoModalState();
}

class _AddEditTodoModalState extends ConsumerState<AddEditTodoModal> {
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  String? _dueDate;
  late String _selectedAssigneeOption;
  String? _titleError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.existingTodo?.title ?? '');
    _notesController =
        TextEditingController(text: widget.existingTodo?.notes ?? '');
    _dueDate = widget.existingTodo?.dueDate;

    if (widget.existingTodo != null) {
      if (widget.existingTodo!.assignedTo == widget.currentUserId) {
        _selectedAssigneeOption = 'me';
      } else if (widget.partnerId != null &&
          widget.existingTodo!.assignedTo == widget.partnerId) {
        _selectedAssigneeOption = 'partner';
      } else {
        _selectedAssigneeOption = 'shared';
      }
    } else {
      _selectedAssigneeOption = 'me';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    DateTime initial = DateTime.now();
    if (_dueDate != null && _dueDate!.isNotEmpty) {
      final parsed = DateTime.tryParse(_dueDate!);
      if (parsed != null) initial = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (picked != null) {
      final formatted =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _dueDate = formatted;
      });
    }
  }

  Future<void> _handleSubmit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = 'Title is required';
      });
      return;
    }

    setState(() {
      _titleError = null;
      _isSubmitting = true;
    });

    final apiClient = ref.read(apiClientProvider);
    final notifier = ref.read(podTodosProvider(widget.podId).notifier);

    String? assignedToId;
    if (_selectedAssigneeOption == 'me') {
      assignedToId = widget.currentUserId;
    } else if (_selectedAssigneeOption == 'partner') {
      assignedToId = widget.partnerId;
    } else {
      assignedToId = null;
    }

    final notes = _notesController.text.trim();

    TodoModel? result;
    if (widget.existingTodo == null) {
      result = await notifier.createTodo(
        apiClient: apiClient,
        title: title,
        notes: notes.isNotEmpty ? notes : null,
        dueDate: _dueDate,
        assignedTo: assignedToId,
      );
    } else {
      result = await notifier.updateTodo(
        apiClient: apiClient,
        todoId: widget.existingTodo!.id,
        title: title,
        notes: notes,
        clearNotes: notes.isEmpty,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        assignedTo: assignedToId,
        clearAssigned: assignedToId == null,
      );
    }

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (result != null) {
        Navigator.of(context).pop(result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingTodo != null;

    final partnerDisplay = widget.partnerName?.isNotEmpty == true
        ? widget.partnerName!
        : 'Partner';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Task' : 'Add New Task',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Title Field
              TextField(
                controller: _titleController,
                autofocus: !isEditing,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Task Title *',
                  hintText: 'e.g. Read 20 pages',
                  errorText: _titleError,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                ),
                onChanged: (val) {
                  if (_titleError != null && val.trim().isNotEmpty) {
                    setState(() {
                      _titleError = null;
                    });
                  }
                },
              ),

              const SizedBox(height: AppSpacing.md),

              // Notes Field
              TextField(
                controller: _notesController,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Add details or context for your partner',
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Assignee Selector
              Text(
                'ASSIGN TO',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    const ButtonSegment<String>(
                      value: 'me',
                      label: Text('Me'),
                      icon: Icon(Icons.person_rounded),
                    ),
                    ButtonSegment<String>(
                      value: 'partner',
                      label: Text(partnerDisplay),
                      icon: const Icon(Icons.person_outline_rounded),
                    ),
                    const ButtonSegment<String>(
                      value: 'shared',
                      label: Text('Shared'),
                      icon: Icon(Icons.group_rounded),
                    ),
                  ],
                  selected: {_selectedAssigneeOption},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedAssigneeOption = newSelection.first;
                    });
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Due Date Selector
              Text(
                'DUE DATE',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusMd,
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.calendar_today_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    _dueDate != null ? 'Due: $_dueDate' : 'No due date set',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: _dueDate != null
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: _dueDate != null
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          tooltip: 'Remove due date',
                          onPressed: () {
                            setState(() {
                              _dueDate = null;
                            });
                          },
                        )
                      : TextButton(
                          onPressed: _pickDueDate,
                          child: const Text('Pick Date'),
                        ),
                  onTap: _pickDueDate,
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusMd,
                    ),
                  ),
                  child: _isSubmitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Text(isEditing ? 'Save Changes' : 'Add Task'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
