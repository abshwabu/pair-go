import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../goals/models/goal_model.dart';
import 'goal_category_provider.dart';

class GoalDetailState {
  final String title;
  final String targetDescription;
  final String pace;
  final bool isLoading;
  final String? errorMessage;
  final String? titleError;

  const GoalDetailState({
    this.title = '',
    this.targetDescription = '',
    this.pace = 'steady',
    this.isLoading = false,
    this.errorMessage,
    this.titleError,
  });

  GoalDetailState copyWith({
    String? title,
    String? targetDescription,
    String? pace,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? titleError,
    bool clearTitleError = false,
  }) {
    return GoalDetailState(
      title: title ?? this.title,
      targetDescription: targetDescription ?? this.targetDescription,
      pace: pace ?? this.pace,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      titleError: clearTitleError ? null : (titleError ?? this.titleError),
    );
  }
}

class GoalDetailNotifier extends Notifier<GoalDetailState> {
  @override
  GoalDetailState build() => const GoalDetailState();

  void setTitle(String value) {
    state = state.copyWith(
      title: value,
      clearTitleError: true,
      clearErrorMessage: true,
    );
  }

  void setTargetDescription(String value) {
    state = state.copyWith(
      targetDescription: value,
      clearErrorMessage: true,
    );
  }

  void setPace(String value) {
    state = state.copyWith(
      pace: value,
      clearErrorMessage: true,
    );
  }

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> submit({
    required ApiClient apiClient,
    required BuildContext context,
  }) async {
    final title = state.title.trim();
    if (title.isEmpty) {
      state = state.copyWith(titleError: 'Goal title is required');
      return;
    }
    if (title.length > 120) {
      state =
          state.copyWith(titleError: 'Title must not exceed 120 characters');
      return;
    }

    final category = ref.read(selectedGoalCategoryProvider) ?? 'custom';

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearTitleError: true,
    );

    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/goals',
        data: {
          'category': category,
          'title': title,
          'target_description': state.targetDescription.trim(),
          'pace': state.pace,
        },
      );

      final goal = GoalModel.fromJson(response.data);
      ref.read(createdGoalProvider.notifier).setGoal(goal);

      state = state.copyWith(isLoading: false);

      if (context.mounted) {
        context.go(AppRoutes.matchingPrefsPath);
      }
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to create goal. Please try again.',
      );
    }
  }
}

final goalDetailNotifierProvider =
    NotifierProvider<GoalDetailNotifier, GoalDetailState>(
  GoalDetailNotifier.new,
);

class CreatedGoalNotifier extends Notifier<GoalModel?> {
  @override
  GoalModel? build() => null;

  void setGoal(GoalModel? goal) {
    state = goal;
  }
}

/// Holds the most recently created goal during onboarding.
final createdGoalProvider =
    NotifierProvider<CreatedGoalNotifier, GoalModel?>(
  CreatedGoalNotifier.new,
);
