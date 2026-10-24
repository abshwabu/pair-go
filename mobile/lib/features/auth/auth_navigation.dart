import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/network/fcm_service.dart';
import '../../core/router.dart';
import '../../core/storage/token_storage.dart';
import 'models/user_model.dart';

/// Validates session via /auth/me and checks /pods:
/// - Routes to pod-home if an active pod exists
/// - Routes to goal-category if no active pod exists
/// - Wipes token and routes to login if absent or invalid
/// - Registers FCM token on successful authentication
Future<void> navigatePostAuth({
  required ApiClient apiClient,
  required TokenStorage tokenStorage,
  required BuildContext context,
  void Function(UserModel user)? onAuthenticated,
  VoidCallback? onLogout,
  FcmService? fcmService,
}) async {
  final hasToken = await tokenStorage.hasToken();
  if (!hasToken) {
    if (context.mounted) {
      context.go(AppRoutes.loginPath);
    }
    return;
  }

  try {
    // 1. Validate session via /auth/me
    final meRes = await apiClient.get<Map<String, dynamic>>('/auth/me');
    final user = UserModel.fromJson(meRes.data);
    onAuthenticated?.call(user);

    // 2. Wire FCM token registration on app start after login
    (fcmService ?? FcmService()).registerFcmToken(apiClient: apiClient);

    // 3. Check active pods via /pods
    final podsRes = await apiClient.get<dynamic>('/pods');
    final pods = podsRes.data;
    final hasActivePod = pods is List && pods.isNotEmpty;

    if (context.mounted) {
      if (hasActivePod) {
        context.go(AppRoutes.podHomePath);
      } else {
        context.go(AppRoutes.goalCategoryPath);
      }
    }
  } catch (_) {
    try {
      await apiClient.post<dynamic>('/auth/logout');
    } catch (_) {}
    await tokenStorage.deleteToken();
    onLogout?.call();
    if (context.mounted) {
      context.go(AppRoutes.loginPath);
    }
  }
}
