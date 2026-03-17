import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  UserModeNotifier() : super(null) {
    _load();
  }

  static const _boxName = 'settings';
  static const _key = 'user_mode';

  void _load() {
    final box = Hive.box(_boxName);
    final saved = box.get(_key);
    if (saved != null) {
      switch (saved) {
        case 'ip': state = UserMode.ip;
        case 'too': state = UserMode.too;
        case 'accountant': state = UserMode.accountant;
      }
    }
  }

  void set(UserMode mode) {
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
    StateNotifierProvider<UserModeNotifier, UserMode?>((ref) => UserModeNotifier());
