import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Режим работы: ИП (учёт своего бизнеса) или Бухгалтер (ведение нескольких клиентов)
enum UserMode { ip, accountant }

extension UserModeExt on UserMode {
  String get label => this == UserMode.ip ? 'ИП' : 'Бухгалтер';
  String get description => this == UserMode.ip
      ? 'Учёт своего бизнеса'
      : 'Веду нескольких клиентов';
}

/// null = не выбран (покажем экран выбора)
final userModeProvider = StateProvider<UserMode?>((ref) => null);
