import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/network/fcm_service.dart';
import '../../core/router.dart';
import '../../core/storage/token_storage.dart';
import '../matching/matching_state_provider.dart';
import '../matching/models/matching_state_model.dart';
import 'models/user_model.dart';

/// Validates session via /auth/me and checks matching state via /matching/current:
/// - Uses routeForState so killing and reopening the app resumes the right screen
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

    // 3. Inspect matching state via GET /api/v1/matching/current
    MatchingStateModel matchingState;
    try {
      final matchRes =
          await apiClient.get<Map<String, dynamic>>('/matching/current');
      matchingState = MatchingStateModel.fromJson(matchRes.data);
    } catch (_) {
      matchingState = const MatchingStateModel(status: MatchingStatus.none);
    }

    if (context.mounted) {
      navigateForMatchingState(context, matchingState, inMatchingFlow: false);
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
