import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'models/in_app_notification_model.dart';

class InAppNotificationsState {
  final List<InAppNotification> notifications;
  final bool isLoading;
  final String? errorMessage;

  const InAppNotificationsState({
    this.notifications = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  InAppNotificationsState copyWith({
    List<InAppNotification>? notifications,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return InAppNotificationsState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class InAppNotificationsNotifier extends Notifier<InAppNotificationsState> {
  @override
  InAppNotificationsState build() {
    return const InAppNotificationsState();
  }

  Future<void> loadNotifications(ApiClient apiClient) async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final res = await apiClient.get<dynamic>('/notifications');
      final list = <InAppNotification>[];
      if (res.data is List) {
        for (final item in res.data as List) {
          if (item is Map<String, dynamic>) {
            list.add(InAppNotification.fromJson(item));
          }
        }
      }
      state = InAppNotificationsState(notifications: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load notifications: $e',
      );
    }
  }

  Future<void> markAsRead(ApiClient apiClient, String id) async {
    try {
      await apiClient.patch<Map<String, dynamic>>('/notifications/$id/read');
      final updated = state.notifications.map((n) {
        if (n.id == id) {
          return n.copyWith(readAt: DateTime.now());
        }
        return n;
      }).toList();
      state = state.copyWith(notifications: updated);
    } catch (_) {}
  }
}

final inAppNotificationsProvider =
    NotifierProvider<InAppNotificationsNotifier, InAppNotificationsState>(
  InAppNotificationsNotifier.new,
);
