// База ИПН с зарплаты = оклад − ОПВ − ВОСМС − 30 МРП (ст. 401 НК РК,
// Закон 214-VIII). До 2026-08-14 код вычитал только ОПВ и 30 МРП — ВОСМС
// терялся, и ИПН завышался на 0.2% оклада (500 ₸ при окладе 250 000).
// Ошибка жила в трёх местах, включая форму 200.00, которая сдаётся в КГД.
//
// Эталон — публичный пример расчёта (mybuh.kz, оклад 300 000 ₸):
//   ОПВ 30 000, ВОСМС 6 000, база 134 250, ИПН 13 425, на руки 250 575,
//   ОПВР 10 500, СО 13 500, ООСМС 9 000.
import 'package:flutter_test/flutter_test.dart';

import 'package:esep/core/models/accounting_client.dart';
import 'package:esep/core/providers/accounting_provider.dart';

void main() {
  test('оклад 300 000 — сходится с эталонным расчётом', () {
    final calc = calcEmployeeSocial(
      const Employee(id: 'e1', name: 'Тест', salary: 300000),
    );

    // closeTo — IEEE double даёт шум вида 10500.000000000002
    expect(calc.opv, closeTo(30000, 0.01));
    expect(calc.vosmsSelf, closeTo(6000, 0.01));
    expect(calc.ipn, closeTo(13425, 0.01)); // было 14 025 — ВОСМС не вычитался
    expect(calc.opvr, closeTo(10500, 0.01));
    expect(calc.so, closeTo(13500, 0.01));
    expect(calc.vosms, closeTo(9000, 0.01)); // ООСМС работодателя
  });

  test('на руки = оклад минус ОПВ, ВОСМС и ИПН', () {
    final calc = calcEmployeeSocial(
      const Employee(id: 'e1', name: 'Тест', salary: 300000),
    );
    expect(300000 - calc.employeeDeductions, closeTo(250575, 0.01));
  });

  test('низкая зарплата: вычеты больше дохода — ИПН ноль, не отрицательный', () {
    final calc = calcEmployeeSocial(
      const Employee(id: 'e2', name: 'Мин', salary: 85000),
    );
    expect(calc.ipn, 0);
  });
}
