// Маппер серверного разбора PDF-выписки Kaspi Gold → KaspiParseResult.
// Сервер (POST /api/import/kaspi-pdf) отдаёт строки вида
// {date: '2026-08-12', amount: 2230, isIncome: false,
//  operation: 'Покупка', details: 'Rancho магазин продуктов'};
// клиент собирает из них тот же KaspiParseResult, что и локальный парсер
// Excel/CSV — предпросмотр, категории и импорт работают без изменений.
import 'package:flutter_test/flutter_test.dart';

import 'package:esep/core/services/kaspi_parser.dart';

void main() {
  final serverJson = {
    'rows': [
      {
        'date': '2026-08-12',
        'amount': 2230,
        'isIncome': false,
        'operation': 'Покупка',
        'details': 'Rancho магазин продуктов',
      },
      {
        'date': '2026-08-11',
        'amount': 149000.5,
        'isIncome': true,
        'operation': 'Пополнение',
        'details': 'С карты другого банка',
      },
      {
        'date': '2026-08-11',
        'amount': 1600,
        'isIncome': false,
        'operation': 'Перевод',
        'details': 'Куандык М.',
      },
      {
        'date': '2025-12-31',
        'amount': 300000,
        'isIncome': true,
        'operation': 'Пополнение',
        'details': '',
      },
    ],
    'warnings': <String>[],
    'count': 4,
  };

  test('строки сервера превращаются в KaspiParseResult', () {
    final r = KaspiParser.fromServerPdf(serverJson);

    expect(r.format, 'kaspi_gold_pdf');
    expect(r.rows, hasLength(4));

    final buy = r.rows[0];
    expect(buy.date, DateTime(2026, 8, 12));
    expect(buy.amount, 2230);
    expect(buy.isIncome, isFalse);
    expect(buy.description, 'Rancho магазин продуктов');

    final income = r.rows[1];
    expect(income.isIncome, isTrue);
    expect(income.amount, 149000.5);
  });

  test('перевод получает контрагента, пустые детали заменяются типом операции', () {
    final r = KaspiParser.fromServerPdf(serverJson);

    final transfer = r.rows[2];
    expect(transfer.counterparty, 'Куандык М.');

    final bare = r.rows[3];
    expect(bare.description, 'Пополнение');
    expect(bare.counterparty, isNull);
  });

  test('предупреждения сервера пробрасываются', () {
    final r = KaspiParser.fromServerPdf({
      'rows': <dynamic>[],
      'warnings': ['В PDF не нашлось операций.'],
    });
    expect(r.rows, isEmpty);
    expect(r.warnings, hasLength(1));
  });
}
