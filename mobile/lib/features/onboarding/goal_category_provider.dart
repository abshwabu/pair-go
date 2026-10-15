import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GoalCategoryInfo {
  final String key;
  final String title;
  final String description;
  final IconData icon;

  const GoalCategoryInfo({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
  });
}

const List<GoalCategoryInfo> kGoalCategories = [
  GoalCategoryInfo(
    key: 'read',
    title: 'Reading',
    description: 'Books, articles, papers, or study',
    icon: Icons.menu_book_rounded,
  ),
  GoalCategoryInfo(
    key: 'watch',
    title: 'Watching',
    description: 'Courses, lectures, or documentaries',
    icon: Icons.play_circle_outline_rounded,
  ),
  GoalCategoryInfo(
    key: 'fitness',
    title: 'Fitness',
    description: 'Running, gym, sports, or movement',
    icon: Icons.fitness_center_rounded,
  ),
  GoalCategoryInfo(
    key: 'habit',
    title: 'Habit',
    description: 'Meditation, journaling, or routine',
    icon: Icons.repeat_rounded,
  ),
  GoalCategoryInfo(
    key: 'custom',
    title: 'Custom',
    description: 'Projects, coding, writing, or skills',
    icon: Icons.stars_rounded,
  ),
];

class SelectedGoalCategoryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? category) {
    state = category;
  }
}

/// Holds the currently selected goal category for onboarding and goal creation.
final selectedGoalCategoryProvider =
    NotifierProvider<SelectedGoalCategoryNotifier, String?>(
  SelectedGoalCategoryNotifier.new,
);
