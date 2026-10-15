import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'models/streak_model.dart';

/// State object managing streak metrics, daily check-in prompt status, and check-in history.
@immutable
class PodStreakState {
  final bool isLoading;
  final bool isCheckingIn;
  final bool isNudging;
  final bool isLoadingHistory;
  final bool isDismissedToday;
  final PodStreakDetails? streak;
  final List<DailyCheckInItem> history;
  final String? errorMessage;
  final String? nudgeStatus;
  final bool? nudgeSuccess;
  final bool hasNudgeRateLimited;

  const PodStreakState({
    this.isLoading = false,
    this.isCheckingIn = false,
    this.isNudging = false,
    this.isLoadingHistory = false,
    this.isDismissedToday = false,
    this.streak,
    this.history = const [],
    this.errorMessage,
    this.nudgeStatus,
    this.nudgeSuccess,
    this.hasNudgeRateLimited = false,
  });

  /// Check if the prompt card should be visible on Pod Home.
  /// Shown if meCheckedInToday is false and user hasn't explicitly dismissed it for this session.
  bool get shouldShowDailyPrompt {
    if (isDismissedToday) return false;
    if (streak == null) return false;
    return !streak!.meCheckedInToday;
  }

  PodStreakState copyWith({
    bool? isLoading,
    bool? isCheckingIn,
    bool? isNudging,
    bool? isLoadingHistory,
    bool? isDismissedToday,
    PodStreakDetails? streak,
    List<DailyCheckInItem>? history,
    String? errorMessage,
    bool clearError = false,
    String? nudgeStatus,
    bool clearNudgeStatus = false,
    bool? nudgeSuccess,
    bool? hasNudgeRateLimited,
  }) {
    return PodStreakState(
      isLoading: isLoading ?? this.isLoading,
      isCheckingIn: isCheckingIn ?? this.isCheckingIn,
      isNudging: isNudging ?? this.isNudging,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      isDismissedToday: isDismissedToday ?? this.isDismissedToday,
      streak: streak ?? this.streak,
      history: history ?? this.history,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      nudgeStatus: clearNudgeStatus ? null : (nudgeStatus ?? this.nudgeStatus),
      nudgeSuccess: clearNudgeStatus ? null : (nudgeSuccess ?? this.nudgeSuccess),
      hasNudgeRateLimited: hasNudgeRateLimited ?? this.hasNudgeRateLimited,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PodStreakState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          isCheckingIn == other.isCheckingIn &&
          isNudging == other.isNudging &&
          isLoadingHistory == other.isLoadingHistory &&
          isDismissedToday == other.isDismissedToday &&
          streak == other.streak &&
          errorMessage == other.errorMessage &&
          nudgeStatus == other.nudgeStatus &&
          nudgeSuccess == other.nudgeSuccess &&
          hasNudgeRateLimited == other.hasNudgeRateLimited &&
          listEquals(history, other.history);

  @override
  int get hashCode => Object.hash(
        isLoading,
        isCheckingIn,
        isNudging,
        isLoadingHistory,
        isDismissedToday,
        streak,
        errorMessage,
        nudgeStatus,
        nudgeSuccess,
        hasNudgeRateLimited,
        Object.hashAll(history),
      );
}

/// Riverpod family Notifier managing a single pod's streak, check-ins, and recovery states.
class PodStreakNotifier extends Notifier<PodStreakState> {
  final String podId;

  PodStreakNotifier(this.podId);

  @override
  PodStreakState build() {
    return const PodStreakState();
  }

  /// Fetches streak metrics from GET /api/v1/pods/{pod}/streak.
  Future<void> fetchStreak(
    ApiClient apiClient, {
    bool forceRefresh = false,
  }) async {
    if (podId.isEmpty) return;
    if (state.streak != null && !forceRefresh && !state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final res = await apiClient.get<Map<String, dynamic>>('/pods/$podId/streak');
      final details = PodStreakDetails.fromJson(res.data);
      state = state.copyWith(
        isLoading: false,
        streak: details,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load streak details.',
      );
    }
  }

  /// Fetches check-in history from GET /api/v1/pods/{pod}/check-ins.
  Future<void> fetchHistory(ApiClient apiClient) async {
    if (podId.isEmpty) return;

    state = state.copyWith(isLoadingHistory: true, clearError: true);

    try {
      final res =
          await apiClient.get<dynamic>('/pods/$podId/check-ins?limit=60');
      final items = <DailyCheckInItem>[];
      if (res.data is List) {
        for (final item in res.data) {
          if (item is Map<String, dynamic>) {
            items.add(DailyCheckInItem.fromJson(item));
          } else if (item is Map) {
            items.add(DailyCheckInItem.fromJson(item.cast<String, dynamic>()));
          }
        }
      }

      state = state.copyWith(
        isLoadingHistory: false,
        history: items,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoadingHistory: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoadingHistory: false,
        errorMessage: 'Failed to load check-in history.',
      );
    }
  }

  /// Records a daily check-in via POST /api/v1/pods/{pod}/check-ins.
  /// On success, directly updates streak state without requiring a full page refetch.
  /// Treats 409 Conflict as "already checked in" and performs a streak refresh.
  Future<bool> checkIn(
    ApiClient apiClient, {
    String? note,
  }) async {
    if (podId.isEmpty) return false;

    state = state.copyWith(isCheckingIn: true, clearError: true);

    try {
      final payload = <String, dynamic>{
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      };

      final res = await apiClient.post<Map<String, dynamic>>(
        '/pods/$podId/check-ins',
        data: payload,
      );

      final result = CheckInResult.fromJson(res.data);

      // Directly update streak metrics from response
      final currentStreakDetails = state.streak;
      final updatedStreak = PodStreakDetails(
        currentStreak: result.currentStreak,
        bestStreak: result.bestStreak,
        lastCheckInDate: result.lastCheckInDate,
        meCheckedInToday: true,
        partnerCheckedInToday:
            currentStreakDetails?.partnerCheckedInToday ?? false,
        bothCheckedInToday: result.checkedInTodayByBoth,
      );

      // If history is loaded, update or prepend today's entry
      final updatedHistory = List<DailyCheckInItem>.from(state.history);
      final todayIndex =
          updatedHistory.indexWhere((h) => h.date == result.checkInDate);
      if (todayIndex >= 0) {
        final existing = updatedHistory[todayIndex];
        final members = Set<String>.from(existing.memberIds)..add(result.userId);
        updatedHistory[todayIndex] = DailyCheckInItem(
          date: existing.date,
          memberIds: members.toList(),
          bothCheckedIn: result.checkedInTodayByBoth,
        );
      } else if (updatedHistory.isNotEmpty) {
        updatedHistory.insert(
          0,
          DailyCheckInItem(
            date: result.checkInDate,
            memberIds: [result.userId],
            bothCheckedIn: result.checkedInTodayByBoth,
          ),
        );
      }

      state = state.copyWith(
        isCheckingIn: false,
        streak: updatedStreak,
        history: updatedHistory,
      );
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409 || e.code == 'CONFLICT') {
        // Treat 409 as already checked in, refresh streak to stay accurate
        await fetchStreak(apiClient, forceRefresh: true);
        state = state.copyWith(isCheckingIn: false);
        return true;
      }

      state = state.copyWith(
        isCheckingIn: false,
        errorMessage: e.message,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isCheckingIn: false,
        errorMessage: 'Failed to record check-in.',
      );
      return false;
    }
  }

  /// Nudges partner to complete their check-in via POST /api/v1/pods/{pod}/nudge.
  /// Rate limited by backend to once every 6 hours (returns 429).
  Future<bool> nudgePartner(ApiClient apiClient) async {
    if (podId.isEmpty) return false;

    state = state.copyWith(
      isNudging: true,
      clearError: true,
      clearNudgeStatus: true,
    );

    try {
      await apiClient.post<Map<String, dynamic>>('/pods/$podId/nudge');

      state = state.copyWith(
        isNudging: false,
        nudgeStatus: 'Nudge sent! Your partner was reminded.',
        nudgeSuccess: true,
        hasNudgeRateLimited: false,
      );
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 429 || e.code == 'RATE_LIMITED') {
        state = state.copyWith(
          isNudging: false,
          nudgeStatus: 'You already nudged recently',
          nudgeSuccess: false,
          hasNudgeRateLimited: true,
        );
        return false;
      }

      state = state.copyWith(
        isNudging: false,
        nudgeStatus: e.message,
        nudgeSuccess: false,
        hasNudgeRateLimited: false,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isNudging: false,
        nudgeStatus: 'Failed to send nudge.',
        nudgeSuccess: false,
        hasNudgeRateLimited: false,
      );
      return false;
    }
  }

  /// Dismisses the daily check-in card for the current session.
  void dismissDailyPrompt() {
    state = state.copyWith(isDismissedToday: true);
  }

  /// Clears active nudge status messages.
  void clearNudgeStatus() {
    state = state.copyWith(clearNudgeStatus: true);
  }
}

/// Single Riverpod provider per pod managing streak metrics, check-in prompts, and history.
final podStreakProvider =
    NotifierProvider.family<PodStreakNotifier, PodStreakState, String>(
  (podId) => PodStreakNotifier(podId),
);
