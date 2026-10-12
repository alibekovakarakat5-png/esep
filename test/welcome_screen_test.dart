import 'dart:io';
import 'package:esep/core/providers/auth_provider.dart';
import 'package:esep/core/providers/user_mode_provider.dart';
import 'package:esep/core/router/app_router.dart';
import 'package:esep/features/onboarding/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('esep_welcome_');
    Hive.init(temp.path);
    await Hive.openBox('settings');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.box('settings').clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets('guide explains limits and works at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: WelcomeScreen(roleHint: 'clients'))));
      await tester.pumpAndSettle();
      expect(find.text('Начните с одного клиента'), findsOneWidget);
      await tester.tap(find.text('Для своего бизнеса'));
      await tester.pumpAndSettle();
      expect(find.text('Начните с одной операции'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Я пришёл из Telegram. Где мои списки?'), 180);
      await tester.tap(find.text('Я пришёл из Telegram. Где мои списки?'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining(
              'перенос документов и переписки пока не подключён'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'public guide survives auth and a hint never silently changes the account mode',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    router.go('/welcome?role=clients');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/welcome');
    expect(container.read(userModeProvider), isNull);
    await tester.scrollUntilVisible(find.text('Перейти к клиентам'), 160);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Перейти к клиентам'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перейти к клиентам'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(),
        '/auth?welcome=clients');
    container.read(authProvider.notifier).enterDemo();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(),
        '/welcome?role=clients');
    expect(container.read(userModeProvider), isNull);
    expect(find.text('Начните с одного клиента'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Hive.box('settings').flush());
  });
}
