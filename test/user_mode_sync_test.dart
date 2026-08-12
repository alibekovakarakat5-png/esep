// Серверная синхронизация режима (ИП/ТОО/Бухгалтер).
//
// До фикса режим жил только в Hive браузера и стирался на logout — каждый
// вход (или новое устройство) снова спрашивал «Кто вы?». Теперь сервер
// хранит user_mode в профиле, а applyRemote() применяет его при входе.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:esep/core/providers/user_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('esep_user_mode_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  setUp(() async {
    await Hive.box('settings').clear();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('applyRemote применяет режим с сервера, когда локально не выбран', () {
    final c = makeContainer();
    c.read(userModeProvider.notifier).applyRemote('ip');
    expect(c.read(userModeProvider), UserMode.ip);
    // и персистит в Hive — следующий запуск увидит режим сразу
    expect(Hive.box('settings').get('user_mode'), 'ip');
  });

  test('applyRemote игнорирует мусор и null', () {
    final c = makeContainer();
    c.read(userModeProvider.notifier).applyRemote('bogus');
    expect(c.read(userModeProvider), isNull);
    c.read(userModeProvider.notifier).applyRemote(null);
    expect(c.read(userModeProvider), isNull);
  });

  test('applyRemote не перетирает уже выбранный локально режим', () {
    final c = makeContainer();
    final notifier = c.read(userModeProvider.notifier);
    notifier.applyRemote('accountant');
    expect(c.read(userModeProvider), UserMode.accountant);
    // сервер прислал другое (например, гонка старых данных) — локальный выбор важнее
    notifier.applyRemote('too');
    expect(c.read(userModeProvider), UserMode.accountant);
  });
}
