import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

enum AuthState { loading, authenticated, unauthenticated }

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.loading) {
    _check();
  }

  Future<void> _check() async {
    final logged = await AuthService.isLoggedIn();
    state = logged ? AuthState.authenticated : AuthState.unauthenticated;
  }

  Future<void> login(String email, String password) async {
    await AuthService.login(email, password);
    state = AuthState.authenticated;
  }

  Future<void> register(String email, String password, String name) async {
    await AuthService.register(email, password, name);
    state = AuthState.authenticated;
  }

  Future<void> logout() async {
    await AuthService.logout();
    state = AuthState.unauthenticated;
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
