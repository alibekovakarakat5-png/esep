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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:esep/core/providers/accounting_provider.dart';
import 'package:esep/core/providers/auth_provider.dart';
import 'package:esep/core/providers/demo_provider.dart';
import 'package:esep/core/models/accounting_client.dart';
import 'package:esep/features/accountant/screens/add_accounting_client_screen.dart';

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

  Future<ProviderContainer> withWriter(
      Future<void> Function(AccountingClient) write) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      isDemoProvider.overrideWith((ref) => false),
      accountingClientWriterProvider.overrideWith((ref) => write),
    ]);
    addTearDown(container.dispose);
    await _waitForAuth(container, AuthState.unauthenticated);
    return container;
  }

  const record = AccountingClient(
    id: 'stable-id',
    name: 'Old',
    binOrIin: '',
    entityType: ClientEntityType.too,
    regime: ClientTaxRegime.our,
    employees: [Employee(id: 'e1', name: 'Employee', salary: 100000)],
    feeReceivedThisMonth: true,
    isActive: false,
  );

  test('неудачные add/edit не меняют подтверждённый список', () async {
    var fail = true;
    final container = await withWriter((_) async {
      if (fail) throw Exception('offline');
    });
    final notifier = container.read(accountingProvider.notifier);
    await expectLater(notifier.addClient(record), throwsException);
    expect(container.read(accountingProvider), isEmpty);
    fail = false;
    await notifier.addClient(record);
    await notifier.addClient(record); // retry same server upsert
    expect(container.read(accountingProvider), hasLength(1));
    fail = true;
    await expectLater(
        notifier.updateClient(record.copyWith(name: 'New')), throwsException);
    expect(container.read(accountingProvider).single.name, 'Old');
  });

  test('add публикуется только после подтверждения сервера', () async {
    final pending = Completer<void>();
    final container = await withWriter((_) => pending.future);
    final save = container.read(accountingProvider.notifier).addClient(record);
    expect(container.read(accountingProvider), isEmpty);
    pending.complete();
    await save;
    expect(container.read(accountingProvider).single.id, record.id);
  });

  testWidgets('форма блокирует двойное сохранение и сохраняет ID при retry',
      (tester) async {
    final writes = <AccountingClient>[];
    final pending = Completer<void>();
    final container = await withWriter((client) {
      writes.add(client);
      return writes.length == 1 ? pending.future : Future<void>.value();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const AddAccountingClientScreen()),
                            ),
                        child: const Text('Open')),
                  ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Test company');
    await tester.tap(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить')); // before a frame rebuild
    await tester.pump();
    expect(writes, hasLength(1));
    expect(container.read(accountingProvider), isEmpty);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(AddAccountingClientScreen), findsOneWidget);
    expect(find.text('Test company'), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(2));
    expect(writes[0].id, writes[1].id);
    expect(container.read(accountingProvider), hasLength(1));
    expect(find.byType(AddAccountingClientScreen), findsNothing);
  });

  testWidgets('переименование через форму не удаляет связанные данные',
      (tester) async {
    AccountingClient? saved;
    final container = await withWriter((client) async {
      saved = client;
    });
    await container.read(accountingProvider.notifier).addClient(record);
    saved = null;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const AddAccountingClientScreen(
                                          existing: record)),
                            ),
                        child: const Text('Edit')),
                  ))),
    ));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(saved!.name, 'Renamed');
    expect(saved!.employees.single.id, 'e1');
    expect(saved!.legacyFeeReceived, isTrue);
    expect(saved!.isActive, isFalse);
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
