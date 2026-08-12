import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/api_client.dart';
import 'demo_provider.dart';

/// Режим работы: ИП, ТОО или Бухгалтер
enum UserMode { ip, too, accountant }

extension UserModeExt on UserMode {
  String get label {
    switch (this) {
      case UserMode.ip: return 'ИП';
      case UserMode.too: return 'ТОО';
      case UserMode.accountant: return 'Бухгалтер';
    }
  }

  String get description {
    switch (this) {
      case UserMode.ip: return 'Учёт своего бизнеса';
      case UserMode.too: return 'Учёт компании';
      case UserMode.accountant: return 'Веду нескольких клиентов';
    }
  }
}

class UserModeNotifier extends StateNotifier<UserMode?> {
  final Ref _ref;
  UserModeNotifier(this._ref) : super(null) {
    _load();
  }

  static const _boxName = 'settings';
  static const _key = 'user_mode';

  static UserMode? _parse(String? raw) => switch (raw) {
        'ip' => UserMode.ip,
        'too' => UserMode.too,
        'accountant' => UserMode.accountant,
        _ => null,
      };

  void _load() {
    final saved = _parse(Hive.box(_boxName).get(_key) as String?);
    if (saved != null) state = saved;
  }

  /// Выбор пользователя: локально + в профиль на сервере, чтобы «Кто вы?»
  /// не появлялся при повторном входе и на других устройствах.
  void set(UserMode mode) {
    state = mode;
    Hive.box(_boxName).put(_key, mode.name);
    // Fire-and-forget: офлайн или демо не должны ломать выбор режима.
    if (!_ref.read(isDemoProvider)) {
      ApiClient.patch('/auth/mode', {'mode': mode.name}).catchError((_) => null);
    }
  }

  /// Режим из профиля на сервере (login / auth/me). Локальный выбор важнее:
  /// применяем только если локально ещё ничего не выбрано.
  void applyRemote(String? raw) {
    final mode = _parse(raw);
    if (mode == null || state != null) return;
    state = mode;
    Hive.box(_boxName).put(_key, mode.name);
  }

  void clear() {
    state = null;
    Hive.box(_boxName).delete(_key);
  }
}

/// null = не выбран (покажем экран выбора)
final userModeProvider =
    StateNotifierProvider<UserModeNotifier, UserMode?>(UserModeNotifier.new);
