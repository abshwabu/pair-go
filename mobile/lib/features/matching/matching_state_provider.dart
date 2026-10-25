import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import 'models/matching_state_model.dart';

/// Single routing rule function that maps a [MatchingStateModel] to its respective route path.
/// - matched: pod-home with pod_id (or match-confirmed if inside an active matching transition)
/// - proposed and my_response pending: match-proposal
/// - proposed and my_response accepted: match-pending
/// - searching: finding-match
/// - none: goal-category
String routeForState(MatchingStateModel state, {bool inMatchingFlow = false}) {
  switch (state.status) {
    case MatchingStatus.matched:
      return inMatchingFlow
          ? AppRoutes.matchConfirmedPath
          : AppRoutes.podHomePath;
    case MatchingStatus.proposed:
      if (state.proposal?.myResponse == 'accepted') {
        return AppRoutes.matchPendingPath;
      }
      return AppRoutes.matchProposalPath;
    case MatchingStatus.searching:
      return AppRoutes.findingMatchPath;
    case MatchingStatus.none:
      return AppRoutes.goalCategoryPath;
  }
}

/// Helper to navigate declaratively using [routeForState]. Always uses `context.go`
/// so that Back navigation cannot loop through old matching screens.
void navigateForMatchingState(
  BuildContext context,
  MatchingStateModel state, {
  bool inMatchingFlow = false,
}) {
  final path = routeForState(state, inMatchingFlow: inMatchingFlow);
  if (state.status == MatchingStatus.matched) {
    context.go(path, extra: state.podId);
  } else {
    context.go(path);
  }
}

/// Riverpod AsyncNotifier managing matching state and 3-second polling.
class MatchingStateNotifier extends AsyncNotifier<MatchingStateModel> {
  Timer? _pollTimer;
  int _activeMatchingScreens = 0;
  bool _isAppActive = true;
  String? _pendingBannerMessage;

  @override
  Future<MatchingStateModel> build() async {
    ref.onDispose(() {
      _stopPolling();
    });

    final apiClient = ref.read(apiClientProvider);
    return _fetchCurrentState(apiClient);
  }

  ApiClient get _apiClient => ref.read(apiClientProvider);

  Future<MatchingStateModel> _fetchCurrentState(ApiClient apiClient) async {
    try {
      final res = await apiClient.get<Map<String, dynamic>>('/matching/current');
      final model = MatchingStateModel.fromJson(
        res.data,
        rejectionBannerMessage: _pendingBannerMessage,
      );
      // Clear banner message if not in searching state
      if (!model.isSearching) {
        _pendingBannerMessage = null;
      }
      return model;
    } catch (e) {
      // If error occurs or unauthenticated, default to none
      return MatchingStateModel(
        status: MatchingStatus.none,
        rejectionBannerMessage: _pendingBannerMessage,
      );
    }
  }

  /// Triggers an immediate fetch and updates state.
  Future<MatchingStateModel> refresh() async {
    final model = await _fetchCurrentState(_apiClient);
    state = AsyncData(model);
    return model;
  }

  /// Accepts a match proposal.
  Future<MatchingStateModel> accept(String proposalId) async {
    try {
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/matching/proposals/$proposalId/accept',
      );
      final model = MatchingStateModel.fromJson(res.data);
      state = AsyncData(model);
      return model;
    } on ApiException catch (e) {
      if (e.code == 'proposal_closed' || e.statusCode == 409) {
        await refresh();
      }
      rethrow;
    }
  }

  /// Rejects a match proposal and returns to searching with a friendly banner.
  Future<MatchingStateModel> reject(
    String proposalId, {
    String? bannerMessage,
  }) async {
    _pendingBannerMessage = bannerMessage ??
        "Your last match didn't work out, we're finding you someone new.";
    try {
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/matching/proposals/$proposalId/reject',
      );
      final model = MatchingStateModel.fromJson(
        res.data,
        rejectionBannerMessage: _pendingBannerMessage,
      );
      state = AsyncData(model);
      return model;
    } on ApiException catch (e) {
      if (e.code == 'proposal_closed' || e.statusCode == 409) {
        await refresh();
      }
      rethrow;
    }
  }

  /// Cancels the current matching request or proposal.
  Future<void> cancel() async {
    final reqId = state.value?.requestId;

    if (reqId != null && reqId.isNotEmpty) {
      try {
        await _apiClient.delete<dynamic>('/matching/request/$reqId');
      } catch (_) {}
    }

    _pendingBannerMessage = null;
    const model = MatchingStateModel(status: MatchingStatus.none);
    state = const AsyncData(model);
  }

  /// Starts polling every 3 seconds when a matching screen becomes visible.
  void startScreenPolling() {
    _activeMatchingScreens++;
    _evaluatePolling();
  }

  /// Pauses polling when a matching screen is disposed.
  void stopScreenPolling() {
    if (_activeMatchingScreens > 0) {
      _activeMatchingScreens--;
    }
    _evaluatePolling();
  }

  /// Updates app lifecycle state (pauses polling when backgrounded).
  void setAppLifecycleState(AppLifecycleState lifecycleState) {
    final active = (lifecycleState == AppLifecycleState.resumed);
    if (_isAppActive != active) {
      _isAppActive = active;
      _evaluatePolling();
    }
  }

  void _evaluatePolling() {
    if (_activeMatchingScreens > 0 && _isAppActive) {
      if (_pollTimer == null || !_pollTimer!.isActive) {
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          refresh();
        });
      }
    } else {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void setRejectionBanner(String message) {
    _pendingBannerMessage = message;
    if (state.hasValue) {
      state = AsyncData(
        state.value!.copyWith(rejectionBannerMessage: message),
      );
    }
  }

  void clearRejectionBanner() {
    _pendingBannerMessage = null;
    if (state.hasValue) {
      state = AsyncData(
        state.value!.copyWith(clearBanner: true),
      );
    }
  }
}

/// Global provider for [MatchingStateNotifier].
final matchingStateProvider =
    AsyncNotifierProvider<MatchingStateNotifier, MatchingStateModel>(
  MatchingStateNotifier.new,
);
