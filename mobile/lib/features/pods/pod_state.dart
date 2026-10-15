import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'models/pod_model.dart';

class CurrentPodIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setPodId(String? id) {
    state = id;
  }
}

/// Stores the active pod ID in Riverpod state.
final currentPodIdProvider =
    NotifierProvider<CurrentPodIdNotifier, String?>(
  CurrentPodIdNotifier.new,
);

class ActivePodDetailState {
  final bool isLoading;
  final String? errorMessage;
  final PodDetail? pod;

  const ActivePodDetailState({
    this.isLoading = false,
    this.errorMessage,
    this.pod,
  });

  ActivePodDetailState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    PodDetail? pod,
  }) {
    return ActivePodDetailState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      pod: pod ?? this.pod,
    );
  }
}

class ActivePodDetailNotifier extends Notifier<ActivePodDetailState> {
  @override
  ActivePodDetailState build() => const ActivePodDetailState();

  Future<PodDetail?> loadPod({
    required ApiClient apiClient,
    String? podId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && state.pod != null && (podId == null || state.pod!.id == podId)) {
      return state.pod;
    }

    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    try {
      String resolvedId = podId ?? ref.read(currentPodIdProvider) ?? '';

      // If no ID is passed, check /pods to get the user's active pod
      if (resolvedId.isEmpty) {
        final podsRes = await apiClient.get<dynamic>('/pods');
        final podsList = podsRes.data;
        if (podsList is List && podsList.isNotEmpty) {
          final first = podsList.first as Map<String, dynamic>;
          resolvedId = first['id'] as String? ?? '';
        }
      }

      if (resolvedId.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'No active pod found',
        );
        return null;
      }

      final res = await apiClient.get<Map<String, dynamic>>('/pods/$resolvedId');
      final pod = PodDetail.fromJson(res.data);

      ref.read(currentPodIdProvider.notifier).setPodId(pod.id);
      state = state.copyWith(isLoading: false, pod: pod);
      return pod;
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load pod details',
      );
      return null;
    }
  }

  void clearPod() {
    state = const ActivePodDetailState();
    ref.read(currentPodIdProvider.notifier).setPodId(null);
  }
}

final activePodDetailProvider =
    NotifierProvider<ActivePodDetailNotifier, ActivePodDetailState>(
  ActivePodDetailNotifier.new,
);
