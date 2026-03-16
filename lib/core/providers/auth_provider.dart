import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import 'user_mode_provider.dart';
import 'transaction_provider.dart';
import 'invoice_provider.dart';

enum AuthState { loading, authenticated, unauthenticated }

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  AuthNotifier(this._ref) : super(AuthState.loading) {
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
    _ref.read(userModeProvider.notifier).clear();
    _ref.invalidate(transactionProvider);
    _ref.invalidate(invoiceProvider);
    state = AuthState.unauthenticated;
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));
