import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/user_model.dart';

class AuthState {
  final bool isAuthenticated;
  final UserModel? user;

  const AuthState({
    this.isAuthenticated = false,
    this.user,
  });

  String? get userId => user?.id;

  AuthState copyWith({
    bool? isAuthenticated,
    UserModel? user,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  void setAuthenticated(UserModel user) {
    state = AuthState(isAuthenticated: true, user: user);
  }

  void setUser(UserModel user) {
    state = state.copyWith(user: user);
  }

  void logout() {
    state = const AuthState(isAuthenticated: false, user: null);
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authNotifierProvider).user;
});
