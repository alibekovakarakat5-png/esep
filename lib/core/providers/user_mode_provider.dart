import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Режим работы: ИП (учёт своего бизнеса) или Бухгалтер (ведение нескольких клиентов)
enum UserMode { ip, accountant }

extension UserModeExt on UserMode {
  String get label => this == UserMode.ip ? 'ИП' : 'Бухгалтер';
  String get description => this == UserMode.ip
      ? 'Учёт своего бизнеса'
      : 'Веду нескольких клиентов';
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
      state = saved == 'ip' ? UserMode.ip : UserMode.accountant;
    }
  }

  void set(UserMode mode) {
    state = mode;
    Hive.box(_boxName).put(_key, mode == UserMode.ip ? 'ip' : 'accountant');
  }

  void clear() {
    state = null;
    Hive.box(_boxName).delete(_key);
  }
}

/// null = не выбран (покажем экран выбора)
final userModeProvider =
    StateNotifierProvider<UserModeNotifier, UserMode?>((ref) => UserModeNotifier());
