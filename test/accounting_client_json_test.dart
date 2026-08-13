// Сериализация клиентов бухгалтера для серверного хранения.
//
// До 2026-08-13 модуль бухгалтера жил на демо-данных в памяти: заведённые
// клиенты исчезали при перезагрузке страницы. Контракт — snake_case, как у
// transactions/invoices (иначе GET не парсится и данные «пропадают»).
import 'package:flutter_test/flutter_test.dart';

import 'package:esep/core/models/accounting_client.dart';

void main() {
  final client = AccountingClient(
    id: 'c1',
    name: 'ТОО «Астана Строй»',
    binOrIin: '200540013422',
    entityType: ClientEntityType.too,
    regime: ClientTaxRegime.our,
    monthlyFee: 25000,
    feeReceivedThisMonth: true,
    notes: 'НДС с сентября',
    employees: const [Employee(id: 'e1', name: 'Иванов А.А.', salary: 150000)],
    checklist: const [
      DocChecklistItem(id: 'd1', label: 'Банковская выписка', received: true),
      DocChecklistItem(id: 'd2', label: 'Акты'),
    ],
  );

  test('toJson отдаёт snake_case и разворачивает вложенные списки', () {
    final j = client.toJson();
    expect(j['bin_or_iin'], '200540013422');
    expect(j['entity_type'], 'too');
    expect(j['regime'], 'our');
    expect(j['monthly_fee'], 25000);
    expect(j['fee_received_this_month'], isTrue);
    expect(j['is_active'], isTrue);
    expect((j['employees'] as List).first['salary'], 150000);
    expect((j['checklist'] as List).last['received'], isFalse);
  });

  test('fromJson восстанавливает клиента без потерь', () {
    final restored = AccountingClient.fromJson(client.toJson());

    expect(restored.id, client.id);
    expect(restored.name, client.name);
    expect(restored.binOrIin, client.binOrIin);
    expect(restored.entityType, ClientEntityType.too);
    expect(restored.regime, ClientTaxRegime.our);
    expect(restored.monthlyFee, 25000);
    expect(restored.feeReceivedThisMonth, isTrue);
    expect(restored.notes, 'НДС с сентября');
    expect(restored.employees.single.name, 'Иванов А.А.');
    expect(restored.checklist.map((d) => d.received), [true, false]);
  });

  test('fromJson переживает неизвестные значения и пропуски', () {
    final restored = AccountingClient.fromJson({
      'id': 'c2',
      'name': 'ИП без полей',
      'bin_or_iin': '',
      'entity_type': 'что-то новое',
      'regime': null,
      // сумма может прийти строкой из pg NUMERIC
      'monthly_fee': '12000.50',
    });

    expect(restored.entityType, ClientEntityType.ip); // безопасное умолчание
    expect(restored.regime, ClientTaxRegime.simplified910);
    expect(restored.monthlyFee, 12000.5);
    expect(restored.employees, isEmpty);
    expect(restored.checklist, isEmpty);
    expect(restored.isActive, isTrue);
  });
}
