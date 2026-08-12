// Гейт загрузки по авторизации: до входа transactionProvider и
// invoiceProvider не должны дёргать API. До фикса при открытии страницы
// уходило 4 запроса без токена (по два GET /transactions и /invoices,
// все 401): дашборд монтируется, пока authProvider ещё loading, а смена
// loading → unauthenticated пересоздавала провайдеры и грузила повторно.
//
// Сети в юнит-тесте нет, поэтому индикатор «загрузка случилась» —
// демо-режим: демо-ветка _load() кладёт данные в state синхронно и без
// HTTP. Если бы нотифаер грузил при создании до входа, демо-данные
// оказались бы в state сразу — тест бы это поймал.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:esep/core/providers/auth_provider.dart';
import 'package:esep/core/providers/demo_provider.dart';
import 'package:esep/core/providers/invoice_provider.dart';
import 'package:esep/core/providers/transaction_provider.dart';

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
    // Hive как в widget_test: logout() чистит user_mode в box('settings').
    final dir = await Directory.systemTemp.createTemp('esep_auth_gating_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  test(
      'до входа данные не грузятся, после входа появляются, '
      'после выхода очищаются', () async {
    SharedPreferences.setMockInitialValues({}); // токена нет
    final container = ProviderContainer(overrides: [
      isDemoProvider.overrideWith((ref) => true),
    ]);
    addTearDown(container.dispose);

    // Как дашборд при старте: подписки живут с первого кадра.
    container.listen(transactionProvider, (_, __) {});
    container.listen(invoiceProvider, (_, __) {});

    // Пока auth инициализируется (loading) — никакой загрузки.
    expect(container.read(authProvider), AuthState.loading);
    expect(container.read(transactionProvider), isEmpty);
    expect(container.read(invoiceProvider), isEmpty);

    // Токена нет → unauthenticated; пересоздание провайдеров не грузит.
    await _waitForAuth(container, AuthState.unauthenticated);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(transactionProvider), isEmpty);
    expect(container.read(invoiceProvider), isEmpty);

    // Вход (демо = authenticated без HTTP) → загрузка стартует.
    container.read(authProvider.notifier).enterDemo();
    await _waitForAuth(container, AuthState.authenticated);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(transactionProvider), isNotEmpty);
    expect(container.read(invoiceProvider), isNotEmpty);
    expect(container.read(transactionLoadingProvider), isFalse);
    expect(container.read(invoiceLoadingProvider), isFalse);

    // Выход: данные очищаются, повторная загрузка не запускается.
    await container.read(authProvider.notifier).logout();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authProvider), AuthState.unauthenticated);
    expect(container.read(transactionProvider), isEmpty);
    expect(container.read(invoiceProvider), isEmpty);
  });
}
