import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'models/todo_model.dart';

enum TodoFilterType { all, mine, partner, shared }

class PodTodosState {
  final List<TodoModel> todos;
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;
  final TodoFilterType filter;

  const PodTodosState({
    this.todos = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.filter = TodoFilterType.all,
  });

  PodTodosState copyWith({
    List<TodoModel>? todos,
    bool? isLoading,
    bool? isSubmitting,
    String? errorMessage,
    bool clearErrorMessage = false,
    TodoFilterType? filter,
  }) {
    return PodTodosState(
      todos: todos ?? this.todos,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      filter: filter ?? this.filter,
    );
  }

  /// Client-side filtered list based on the active filter chip.
  List<TodoModel> filteredTodos(String currentUserId, String? partnerId) {
    switch (filter) {
      case TodoFilterType.mine:
        return todos.where((t) => t.assignedTo == currentUserId).toList();
      case TodoFilterType.partner:
        if (partnerId == null || partnerId.isEmpty) return [];
        return todos.where((t) => t.assignedTo == partnerId).toList();
      case TodoFilterType.shared:
        return todos.where((t) => t.isShared).toList();
      case TodoFilterType.all:
        return todos;
    }
  }

  /// Open todos under the active filter.
  List<TodoModel> openTodos(String currentUserId, String? partnerId) {
    return filteredTodos(currentUserId, partnerId)
        .where((t) => !t.isDone)
        .toList();
  }

  /// Completed todos under the active filter.
  List<TodoModel> doneTodos(String currentUserId, String? partnerId) {
    return filteredTodos(currentUserId, partnerId)
        .where((t) => t.isDone)
        .toList();
  }

  /// Top 3 open todos for the pod (used by the Pod Home preview widget).
  List<TodoModel> get top3OpenTodos {
    return todos.where((t) => !t.isDone).take(3).toList();
  }
}

class PodTodosNotifier extends Notifier<PodTodosState> {
  final String podId;

  PodTodosNotifier(this.podId);

  @override
  PodTodosState build() {
    return const PodTodosState();
  }

  void setFilter(TodoFilterType filter) {
    state = state.copyWith(filter: filter);
  }

  /// Fetches the full list of todos for the pod.
  Future<void> fetchTodos({
    required ApiClient apiClient,
    bool forceRefresh = false,
  }) async {
    if (podId.isEmpty) return;
    if (!forceRefresh && state.todos.isNotEmpty) return;

    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    try {
      final res = await apiClient.get<dynamic>('/pods/$podId/todos');
      final data = res.data;

      List<TodoModel> items = [];
      if (data is List) {
        items = data
            .map((item) => TodoModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      state = state.copyWith(
        todos: items,
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load todos.',
      );
    }
  }

  /// Optimistically toggles is_done on a todo.
  /// If the API call fails, rolls back the change and returns false.
  Future<bool> toggleTodoOptimistic({
    required ApiClient apiClient,
    required String todoId,
  }) async {
    final index = state.todos.indexWhere((t) => t.id == todoId);
    if (index == -1) return false;

    final oldTodo = state.todos[index];
    final targetDone = !oldTodo.isDone;

    // 1. Optimistic update
    final optimisticTodo = oldTodo.copyWith(
      isDone: targetDone,
      completedAt: targetDone ? DateTime.now().toUtc() : null,
      clearCompletedAt: !targetDone,
    );

    final updatedList = List<TodoModel>.from(state.todos);
    updatedList[index] = optimisticTodo;
    state = state.copyWith(todos: updatedList);

    // 2. Perform API call
    try {
      final res = await apiClient.patch<Map<String, dynamic>>(
        '/pods/$podId/todos/$todoId',
        data: {'is_done': targetDone},
      );

      final confirmedTodo = TodoModel.fromJson(res.data);
      final finalConfirmedList = List<TodoModel>.from(state.todos);
      final confirmedIndex =
          finalConfirmedList.indexWhere((t) => t.id == todoId);
      if (confirmedIndex != -1) {
        finalConfirmedList[confirmedIndex] = confirmedTodo;
        state = state.copyWith(todos: finalConfirmedList);
      }
      return true;
    } catch (_) {
      // 3. Roll back on failure
      final rollbackList = List<TodoModel>.from(state.todos);
      final rollbackIndex = rollbackList.indexWhere((t) => t.id == todoId);
      if (rollbackIndex != -1) {
        rollbackList[rollbackIndex] = oldTodo;
        state = state.copyWith(
          todos: rollbackList,
          errorMessage: 'Failed to update task. Reverted changes.',
        );
      }
      return false;
    }
  }

  /// Creates a new todo in the pod.
  Future<TodoModel?> createTodo({
    required ApiClient apiClient,
    required String title,
    String? notes,
    String? dueDate,
    String? assignedTo,
  }) async {
    state = state.copyWith(isSubmitting: true, clearErrorMessage: true);

    try {
      final payload = <String, dynamic>{
        'title': title.trim(),
        if (notes != null && notes.trim().isNotEmpty)
          'notes': notes.trim(),
        if (dueDate != null && dueDate.trim().isNotEmpty)
          'due_date': dueDate.trim(),
        'assigned_to': (assignedTo != null && assignedTo.isNotEmpty && assignedTo != 'shared')
            ? assignedTo
            : null,
      };

      final res = await apiClient.post<Map<String, dynamic>>(
        '/pods/$podId/todos',
        data: payload,
      );

      final newTodo = TodoModel.fromJson(res.data);
      state = state.copyWith(
        todos: [newTodo, ...state.todos],
        isSubmitting: false,
      );
      return newTodo;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to create task.',
      );
      return null;
    }
  }

  /// Updates an existing todo.
  Future<TodoModel?> updateTodo({
    required ApiClient apiClient,
    required String todoId,
    String? title,
    String? notes,
    bool clearNotes = false,
    String? dueDate,
    bool clearDueDate = false,
    String? assignedTo,
    bool clearAssigned = false,
    bool? isDone,
  }) async {
    state = state.copyWith(isSubmitting: true, clearErrorMessage: true);

    try {
      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title.trim();
      if (clearNotes) {
        payload['notes'] = null;
      } else if (notes != null) {
        payload['notes'] = notes.trim();
      }
      if (clearDueDate) {
        payload['due_date'] = null;
      } else if (dueDate != null) {
        payload['due_date'] = dueDate.trim();
      }
      if (clearAssigned) {
        payload['assigned_to'] = null;
      } else if (assignedTo != null) {
        payload['assigned_to'] =
            (assignedTo.isNotEmpty && assignedTo != 'shared') ? assignedTo : null;
      }
      if (isDone != null) payload['is_done'] = isDone;

      final res = await apiClient.patch<Map<String, dynamic>>(
        '/pods/$podId/todos/$todoId',
        data: payload,
      );

      final updated = TodoModel.fromJson(res.data);
      final updatedList = state.todos.map((t) {
        return t.id == todoId ? updated : t;
      }).toList();

      state = state.copyWith(
        todos: updatedList,
        isSubmitting: false,
      );
      return updated;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to update task.',
      );
      return null;
    }
  }

  /// Deletes a todo from the pod.
  Future<bool> deleteTodo({
    required ApiClient apiClient,
    required String todoId,
  }) async {
    state = state.copyWith(isSubmitting: true, clearErrorMessage: true);

    try {
      await apiClient.delete<Map<String, dynamic>>(
        '/pods/$podId/todos/$todoId',
      );

      state = state.copyWith(
        todos: state.todos.where((t) => t.id != todoId).toList(),
        isSubmitting: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to delete task.',
      );
      return false;
    }
  }
}

/// Single Riverpod FamilyNotifier per pod managing todos, CRUD, and optimistic toggling.
final podTodosProvider =
    NotifierProvider.family<PodTodosNotifier, PodTodosState, String>(
  PodTodosNotifier.new,
);
