// Умный предвыбор галочек при импорте PDF-выписки Kaspi Gold.
//
// Личная карта — всё вперемешку, и снимать 1200 галочек руками нельзя.
// Правила построены по реальной выписке (34 стр, 1429 операций):
//  • доходы-«Пополнения» со своих карт/депозита/зарплата — не выручка → снять
//  • расходы-«Покупки» (магазины/сервисы) — личное → снять
//  • расходы-«Переводы» до 5 000 ₸ — личная мелочь → снять
//  • всё остальное остаётся отмеченным, пользователь только проверяет.
// Для Excel/CSV (operation == null) предвыбор не вмешивается.
import 'package:flutter_test/flutter_test.dart';

import 'package:esep/core/services/import_auto_select.dart';
import 'package:esep/core/services/kaspi_parser.dart';

KaspiRow _row({
  required bool isIncome,
  required double amount,
  String description = 'x',
  String? operation,
}) =>
    KaspiRow(
      date: DateTime(2026, 8, 12),
      amount: amount,
      isIncome: isIncome,
      description: description,
      operation: operation,
    );

void main() {
  test('доход от человека остаётся отмеченным', () {
    expect(
      ImportAutoSelect.suggest(_row(
        isIncome: true, amount: 50000,
        description: 'Айман А.', operation: 'Пополнение',
      )),
      isTrue,
    );
  });

  test('свои деньги: с карты другого банка, депозит, зарплата — снимаются', () {
    for (final d in [
      'С карты другого банка',
      'со С Kaspi Депозита',
      'Зарплата',
    ]) {
      expect(
        ImportAutoSelect.suggest(_row(
          isIncome: true, amount: 100000,
          description: d, operation: 'Пополнение',
        )),
        isFalse,
        reason: d,
      );
    }
  });

  test('покупки в магазинах снимаются, снятие наличных остаётся', () {
    expect(
      ImportAutoSelect.suggest(_row(
        isIncome: false, amount: 2230,
        description: 'Rancho магазин продуктов', operation: 'Покупка',
      )),
      isFalse,
    );
    expect(
      ImportAutoSelect.suggest(_row(
        isIncome: false, amount: 50000,
        description: 'Банкомат', operation: 'Снятие',
      )),
      isTrue,
    );
  });

  test('переводы: мелкие снимаются, крупные остаются', () {
    expect(
      ImportAutoSelect.suggest(_row(
        isIncome: false, amount: 1600,
        description: 'Куандык М.', operation: 'Перевод',
      )),
      isFalse,
    );
    expect(
      ImportAutoSelect.suggest(_row(
        isIncome: false, amount: 150000,
        description: 'ТОО Поставщик', operation: 'Перевод',
      )),
      isTrue,
    );
  });

  test('Excel/CSV (operation == null) — предвыбор не трогает', () {
    expect(
      ImportAutoSelect.suggest(_row(isIncome: false, amount: 110)),
      isTrue,
    );
    expect(
      ImportAutoSelect.suggest(_row(isIncome: true, amount: 100)),
      isTrue,
    );
  });
}
