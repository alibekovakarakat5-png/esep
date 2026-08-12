// Смок-тест: приложение поднимается без исключений.
//
// Прежняя версия не проходила никогда: пампила EsepApp без инициализации
// Hive (роутер читает box('settings') уже на редиректе) и искала текст
// «Есеп» кириллицей, которого в UI нет (в шапке — латинское «Esep»).
// Обнаружено при включении flutter test в CI 2026-08-06.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:esep/app.dart';

void main() {
  setUpAll(() async {
    // Hive во временной директории — как в main(), но без flutter-плагинов.
    final dir = await Directory.systemTemp.createTemp('esep_widget_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  testWidgets('EsepApp запускается без исключений', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EsepApp()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('тема всегда светлая — тёмная не спроектирована', (tester) async {
    // Половина цветов захардкожена под светлый фон: в системной тёмной теме
    // текст пропадал (имена банков тёмным по тёмному, серый текст на белых
    // карточках). До полноценного редизайна тёмной темы следовать системной
    // нельзя. Найдено Каракат 2026-08-12 на тёмной теме Windows.
    await tester.pumpWidget(const ProviderScope(child: EsepApp()));
    await tester.pump(const Duration(milliseconds: 100));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
  });
}
