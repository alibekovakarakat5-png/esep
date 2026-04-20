import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import 'user_mode_provider.dart';
import 'transaction_provider.dart';
import 'invoice_provider.dart';
import 'demo_provider.dart';
import 'subscription_provider.dart';

enum AuthState { loading, authenticated, unauthenticated }

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  AuthNotifier(this._ref) : super(AuthState.loading) {
    _check();
  }

  Future<void> _check() async {
    final logged = await AuthService.isLoggedIn();
    if (logged) {
      try {
        final snapshot = await AuthService.me();
        _ref.read(subscriptionProvider.notifier).applyServerSnapshot(snapshot);
        state = AuthState.authenticated;
      } catch (_) {
        await AuthService.logout();
        state = AuthState.unauthenticated;
      }
    } else {
      state = AuthState.unauthenticated;
    }
  }

  Future<void> login(String email, String password) async {
    final snapshot = await AuthService.login(email, password);
    _ref.read(isDemoProvider.notifier).state = false;
    _ref.read(subscriptionProvider.notifier).applyServerSnapshot(snapshot);
    state = AuthState.authenticated;
  }

  Future<void> register(String email, String password, String name) async {
    final snapshot = await AuthService.register(email, password, name);
    _ref.read(isDemoProvider.notifier).state = false;
    _ref.read(subscriptionProvider.notifier).applyServerSnapshot(snapshot);
    state = AuthState.authenticated;
  }

  /// Enter demo mode without server auth
  void enterDemo() {
    _ref.read(isDemoProvider.notifier).state = true;
    state = AuthState.authenticated;
  }

  Future<void> logout() async {
    final wasDemo = _ref.read(isDemoProvider);
    _ref.read(isDemoProvider.notifier).state = false;
    if (!wasDemo) {
      await AuthService.logout();
    }
    _ref.read(userModeProvider.notifier).clear();
    _ref.invalidate(transactionProvider);
    _ref.invalidate(invoiceProvider);
    state = AuthState.unauthenticated;
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));
