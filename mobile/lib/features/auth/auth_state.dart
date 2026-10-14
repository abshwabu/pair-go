import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthState {
  final bool isAuthenticated;
  final String? userId;

  const AuthState({this.isAuthenticated = false, this.userId});
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  void setAuthenticated(String userId) {
    state = AuthState(isAuthenticated: true, userId: userId);
  }

  void logout() {
    state = const AuthState(isAuthenticated: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
