// Клиенты бухгалтера грузятся с сервера, а демо-данные остаются только в
// демо-режиме.
//
// Было: AccountingNotifier() : super(_demoClients()) — модуль стартовал с
// пяти вымышленных клиентов, а заведённые пользователем исчезали при
// перезагрузке. Плюс тот же гейт, что у transactions/invoices: до входа
// запросов быть не должно (иначе 401 без токена).
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:esep/core/providers/accounting_provider.dart';
import 'package:esep/core/providers/auth_provider.dart';
import 'package:esep/core/providers/demo_provider.dart';

Future<void> _waitForAuth(ProviderContainer container, AuthState want) async {
  if (container.read(authProvider) == want) return;
  final done = Completer<void>();
  final sub = container.listen<AuthState>(authProvider, (_, next) {
    if (next == want && !done.isCompleted) done.complete();
  });
  await done.future.timeout(const Duration(seconds: 5));
  sub.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('esep_accounting_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  test('до входа список пуст, демо-режим показывает демо-клиентов', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.listen(accountingProvider, (_, __) {});

    // Пока авторизация не прошла — ни демо, ни запросов на сервер.
    expect(container.read(authProvider), AuthState.loading);
    expect(container.read(accountingProvider), isEmpty);

    await _waitForAuth(container, AuthState.unauthenticated);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(accountingProvider), isEmpty);

    // Демо-вход: клиенты-примеры появляются без сети.
    container.read(authProvider.notifier).enterDemo();
    await _waitForAuth(container, AuthState.authenticated);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(accountingProvider), isNotEmpty);
    expect(container.read(accountingLoadingProvider), isFalse);
  });

  test('в обычном режиме демо-клиенты не подставляются', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      isDemoProvider.overrideWith((ref) => false),
    ]);
    addTearDown(container.dispose);

    container.listen(accountingProvider, (_, __) {});
    await _waitForAuth(container, AuthState.unauthenticated);
    await Future<void>.delayed(Duration.zero);

    // Сети в тесте нет: важно, что вместо демо-данных остаётся пустой список,
    // иначе бухгалтер увидит чужие вымышленные ИП вместо своих клиентов.
    expect(container.read(accountingProvider), isEmpty);
  });
}
