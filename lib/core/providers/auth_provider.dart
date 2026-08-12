import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import 'user_mode_provider.dart';
import 'demo_provider.dart';
import 'subscription_provider.dart';

enum AuthState { loading, authenticated, unauthenticated }

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  AuthNotifier(this._ref) : super(AuthState.loading) {
    _check();
  }

  /// Общий хвост входа: подписка + режим из профиля, затем authenticated.
  /// Режим применяем ДО смены состояния — иначе редирект успеет показать
  /// «Кто вы?» пользователю, который уже выбирал режим раньше.
  void _applySnapshot(AuthSnapshot snapshot) {
    _ref.read(subscriptionProvider.notifier).applyServerSnapshot(snapshot);
    _ref.read(userModeProvider.notifier).applyRemote(snapshot.userMode);
    state = AuthState.authenticated;
  }

  Future<void> _check() async {
    final logged = await AuthService.isLoggedIn();
    if (logged) {
      try {
        _applySnapshot(await AuthService.me());
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
    _applySnapshot(snapshot);
  }

  Future<void> register(
    String email, String password, String name, {
    String? phone,
  }) async {
    final snapshot = await AuthService.register(email, password, name, phone: phone);
    _ref.read(isDemoProvider.notifier).state = false;
    _applySnapshot(snapshot);
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
    // transaction/invoice провайдеры чистить не нужно: они ref.watch(authProvider)
    // и пересоздаются пустыми от смены состояния ниже. invalidate отсюда — это
    // CircularDependencyError в debug (они зависят от authProvider).
    state = AuthState.unauthenticated;
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));
