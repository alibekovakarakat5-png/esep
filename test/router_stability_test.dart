// Роутер не должен пересоздаваться при изменении auth/режима/подписки.
//
// Баг (найден 2026-08-13 при QA бухгалтерского режима): appRouterProvider
// делал ref.watch(_routerListenableProvider), а тот был ChangeNotifierProvider
// — он ре-эмитит значение на КАЖДЫЙ notifyListeners(). Любая смена режима,
// авторизации или подписки пересобирала GoRouter, и навигация сбрасывалась
// на initialLocation '/dashboard'.
//
// Симптом: бухгалтер выбирает «Бухгалтер» → mode_select зовёт
// context.go('/accountant'), но роутер уже новый и стоит на /dashboard —
// бухгалтер видел дашборд ИП («Налог 910», «Загрузите выписку») со своим
// боковым меню. До экрана клиентов штатно было не добраться.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:esep/core/router/app_router.dart';
import 'package:esep/core/providers/user_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('esep_router_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  setUp(() async {
    // authProvider читает токен через SharedPreferences уже в конструкторе.
    SharedPreferences.setMockInitialValues({});
    await Hive.box('settings').clear();
  });

  test('смена режима не пересоздаёт GoRouter', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    container.read(userModeProvider.notifier).set(UserMode.accountant);

    expect(
      identical(container.read(appRouterProvider), router),
      isTrue,
      reason: 'пересоздание роутера сбрасывает навигацию на /dashboard',
    );
  });

  test('роутер знает маршрут бухгалтера', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final config = container.read(appRouterProvider).configuration;
    expect(config.findMatch(Uri.parse('/accountant')).isError, isFalse);
  });
}
