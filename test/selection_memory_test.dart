// Память решений «бизнес/личное» при импорте выписки.
// Пользователь один раз снял галочку с «Rancho магазин продуктов» — в
// следующих выписках Esep снимет её сам; вернул галочку переводу от
// «Айман А.» — навсегда отмечен. Память сильнее правил предвыбора.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:esep/core/services/selection_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('esep_selmem_test');
    Hive.init(dir.path);
    await SelectionMemory.init();
  });

  setUp(() async {
    await Hive.box('selection_memory').clear();
  });

  test('решение запоминается и вспоминается', () async {
    await SelectionMemory.remember('Rancho магазин продуктов', null, false);
    expect(SelectionMemory.recall('Rancho магазин продуктов', null), isFalse);

    await SelectionMemory.remember('Оплата по счёту', 'Айман А.', true);
    expect(SelectionMemory.recall('другое описание', 'Айман А.'), isTrue);
  });

  test('незнакомая операция — null (решают правила предвыбора)', () {
    expect(SelectionMemory.recall('Совершенно новое', null), isNull);
  });

  test('контрагент приоритетнее описания', () async {
    await SelectionMemory.remember('Перевод', 'Айман А.', true);
    await SelectionMemory.remember('Перевод', null, false);
    expect(SelectionMemory.recall('Перевод', 'Айман А.'), isTrue);
    expect(SelectionMemory.recall('Перевод', null), isFalse);
  });
}
