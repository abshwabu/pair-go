import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';
import 'api_client.dart';
import '../../features/account/notification_preferences_provider.dart';
import '../../features/auth/auth_state.dart';

/// Service responsible for FCM device token registration, refresh handling,
/// client-side push notification filtering based on user preferences, and logout.
class FcmService {
  final Ref? _ref;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  bool _initialized = false;

  FcmService([this._ref]);

  /// Requests notification permissions, retrieves the FCM token, and registers
  /// it with the Go backend via PATCH /api/v1/profile/fcm-token.
  Future<void> registerFcmToken({required ApiClient apiClient}) async {
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        if (kDebugMode) {
          debugPrint('Firebase not initialized; skipping FCM token registration.');
        }
        return;
      }

      final messaging = FirebaseMessaging.instance;

      // 1. Request notification permissions
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) {
          debugPrint('User denied notification permissions.');
        }
        return;
      }

      // 2. Get device token
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _sendTokenToBackend(apiClient, token);
      }

      // 3. Listen for token refreshes
      await _tokenRefreshSub?.cancel();
      // ignore: deprecated_member_use
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        if (newToken.isNotEmpty) {
          await _sendTokenToBackend(apiClient, newToken);
        }
      });

      // 4. Listen for incoming foreground messages and apply client-side filtering
      if (!_initialized) {
        _initialized = true;
        await _messageSub?.cancel();
        _messageSub =
            FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          _handleForegroundMessage(message);
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'FCM service initialization skipped or encountered error: $e');
      }
    }
  }

  Future<void> _sendTokenToBackend(ApiClient apiClient, String token) async {
    try {
      await apiClient.patch<Map<String, dynamic>>(
        '/profile/fcm-token',
        data: {'fcm_token': token},
      );
      if (kDebugMode) {
        debugPrint('FCM token successfully registered with backend.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to send FCM token to backend: $e');
      }
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final type = message.data['type'] as String? ?? 'general';
    final prefs = _ref?.read(notificationPreferencesProvider);

    // Client-side filtering MVP: check whether this notification type is enabled
    final isAllowed = prefs?.isEnabled(type) ?? true;
    if (!isAllowed) {
      if (kDebugMode) {
        debugPrint(
            'FCM notification type "$type" filtered out by user preference.');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('FCM notification allowed for type: $type');
    }
  }

  /// On logout: calls POST /auth/logout, clears stored token, and resets auth state.
  Future<void> logout({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
    required WidgetRef ref,
  }) async {
    try {
      await apiClient.post<dynamic>('/auth/logout');
    } catch (_) {}

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    await tokenStorage.deleteToken();
    ref.read(authNotifierProvider.notifier).logout();
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _messageSub?.cancel();
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  final service = FcmService(ref);
  ref.onDispose(service.dispose);
  return service;
});
