import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../onboarding/goal_detail_provider.dart';
import '../onboarding/matching_prefs_provider.dart';
import '../pods/pod_state.dart';
import 'models/matching_request_model.dart';

class FindingMatchState {
  final bool isSubmitting;
  final bool isPolling;
  final bool isCancelling;
  final String? errorMessage;
  final MatchingRequestModel? request;
  final int statusTextIndex;
  final String? matchedPodId;
  final bool shouldRouteToGoalCategory;

  const FindingMatchState({
    this.isSubmitting = true,
    this.isPolling = false,
    this.isCancelling = false,
    this.errorMessage,
    this.request,
    this.statusTextIndex = 0,
    this.matchedPodId,
    this.shouldRouteToGoalCategory = false,
  });

  FindingMatchState copyWith({
    bool? isSubmitting,
    bool? isPolling,
    bool? isCancelling,
    String? errorMessage,
    bool clearErrorMessage = false,
    MatchingRequestModel? request,
    int? statusTextIndex,
    String? matchedPodId,
    bool? shouldRouteToGoalCategory,
  }) {
    return FindingMatchState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isPolling: isPolling ?? this.isPolling,
      isCancelling: isCancelling ?? this.isCancelling,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      request: request ?? this.request,
      statusTextIndex: statusTextIndex ?? this.statusTextIndex,
      matchedPodId: matchedPodId ?? this.matchedPodId,
      shouldRouteToGoalCategory:
          shouldRouteToGoalCategory ?? this.shouldRouteToGoalCategory,
    );
  }
}

class FindingMatchNotifier extends Notifier<FindingMatchState> {
  Timer? _pollTimer;
  Timer? _statusTextTimer;

  static const List<String> statusMessages = [
    'Searching for your accountability partner...',
    'Matching goal pace and category...',
    'Checking timezone compatibility...',
    'Finding an active accountability buddy...',
  ];

  @override
  FindingMatchState build() {
    ref.onDispose(() {
      _stopTimers();
    });
    return const FindingMatchState();
  }

  void _startStatusTextRotation() {
    _statusTextTimer?.cancel();
    _statusTextTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      state = state.copyWith(
        statusTextIndex: (state.statusTextIndex + 1) % statusMessages.length,
      );
    });
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _statusTextTimer?.cancel();
    _statusTextTimer = null;
  }

  /// Public method to stop timers explicitly when screen is disposed
  void stopPolling() {
    _stopTimers();
  }

  /// Initiates or resumes the matching request without needing BuildContext.
  Future<void> startMatching({required ApiClient apiClient}) async {
    _startStatusTextRotation();
    state = state.copyWith(
      isSubmitting: true,
      clearErrorMessage: true,
    );

    // 1. Resolve goal ID from createdGoalProvider, or fetch user's goals
    String? goalId = ref.read(createdGoalProvider)?.id;
    if (goalId == null || goalId.isEmpty) {
      try {
        final goalsRes = await apiClient.get<dynamic>('/goals');
        final goalsData = goalsRes.data;
        if (goalsData is List && goalsData.isNotEmpty) {
          final first = goalsData.first as Map<String, dynamic>;
          goalId = first['id'] as String?;
        }
      } catch (_) {
        // Ignored, handled below
      }
    }

    if (goalId == null || goalId.isEmpty) {
      state = state.copyWith(
        isSubmitting: false,
        shouldRouteToGoalCategory: true,
        errorMessage: 'No goal found to match. Please set up a goal first.',
      );
      return;
    }

    final timezoneTolerance =
        ref.read(matchingPrefsNotifierProvider).timezoneToleranceHours;

    try {
      final res = await apiClient.post<Map<String, dynamic>>(
        '/matching/request',
        data: {
          'goal_id': goalId,
          'timezone_tolerance_hours': timezoneTolerance,
        },
      );

      final matchRequest = MatchingRequestModel.fromJson(res.data);
      state = state.copyWith(
        isSubmitting: false,
        isPolling: true,
        request: matchRequest,
      );

      // If matched instantly by the worker
      if (matchRequest.isMatched && matchRequest.podId != null) {
        _setMatched(matchRequest.podId!);
        return;
      }

      // Otherwise start polling every 5 seconds
      _startPolling(apiClient: apiClient, requestId: matchRequest.id);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _handleConflict(apiClient: apiClient, error: e);
      } else {
        state = state.copyWith(
          isSubmitting: false,
          errorMessage: e.message,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to start matching. Please try again.',
      );
    }
  }

  Future<void> _handleConflict({
    required ApiClient apiClient,
    required ApiException error,
  }) async {
    // Check if user is already in an active pod
    try {
      final podsRes = await apiClient.get<dynamic>('/pods');
      final podsList = podsRes.data;
      if (podsList is List && podsList.isNotEmpty) {
        final firstPod = podsList.first as Map<String, dynamic>;
        final podId = firstPod['id'] as String?;
        if (podId != null && podId.isNotEmpty) {
          _setMatched(podId);
          return;
        }
      }
    } catch (_) {
      // Continue to handle active request
    }

    // Active request conflict: keep animated search state while polling pods every 5s
    state = state.copyWith(
      isSubmitting: false,
      isPolling: true,
      errorMessage: 'You already have an active matching request. Searching...',
    );

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final podsRes = await apiClient.get<dynamic>('/pods');
        final podsList = podsRes.data;
        if (podsList is List && podsList.isNotEmpty) {
          final firstPod = podsList.first as Map<String, dynamic>;
          final podId = firstPod['id'] as String?;
          if (podId != null && podId.isNotEmpty) {
            _setMatched(podId);
          }
        }
      } catch (_) {
        // Retry next tick
      }
    });
  }

  void _startPolling({
    required ApiClient apiClient,
    required String requestId,
  }) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await pollStatus(apiClient: apiClient, requestId: requestId);
    });
  }

  Future<void> pollStatus({
    required ApiClient apiClient,
    required String requestId,
  }) async {
    try {
      final res = await apiClient.get<Map<String, dynamic>>(
        '/matching/request/$requestId',
      );
      final updated = MatchingRequestModel.fromJson(res.data);
      state = state.copyWith(request: updated);

      if (updated.isMatched && updated.podId != null) {
        _setMatched(updated.podId!);
      } else if (updated.isCancelled || updated.isExpired) {
        _stopTimers();
        state = state.copyWith(
          isPolling: false,
          errorMessage: 'Matching request was ${updated.status}.',
        );
      }
    } catch (_) {
      // Temporary network error, continue polling
    }
  }

  void _setMatched(String podId) {
    _stopTimers();
    ref.read(currentPodIdProvider.notifier).setPodId(podId);
    state = state.copyWith(
      isPolling: false,
      matchedPodId: podId,
    );
  }

  /// Cancels the matching request. Returns true if cancellation completed.
  Future<bool> cancelSearch({required ApiClient apiClient}) async {
    _stopTimers();
    state = state.copyWith(isCancelling: true);

    final reqId = state.request?.id;
    if (reqId != null && reqId.isNotEmpty) {
      try {
        await apiClient.delete<Map<String, dynamic>>(
          '/matching/request/$reqId',
        );
      } catch (_) {
        // Ignore errors on delete
      }
    }

    state = state.copyWith(
      isCancelling: false,
      isPolling: false,
      request: null,
    );
    return true;
  }
}

final findingMatchNotifierProvider =
    NotifierProvider.autoDispose<FindingMatchNotifier, FindingMatchState>(
  FindingMatchNotifier.new,
);
