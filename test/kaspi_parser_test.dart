// Тесты парсера банковских выписок: форматы Kaspi, Halyk, Forte, Jusan,
// БЦК, Freedom + казахские заголовки, разные форматы дат и сумм.
//
// Запуск: flutter test test/kaspi_parser_test.dart
//
// Логика продублирована Node-харнессом (scratchpad/test_parser.mjs) — им
// проверяли алгоритм, пока dart.exe заблокирован Device Guard.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:esep/core/services/kaspi_parser.dart';

/// CSV → байты (парсер сам определит разделитель).
List<int> csv(String s) => utf8.encode(s);

void main() {
  group('Даты разных банков', () {
    final cases = {
      '28.07.2026': DateTime(2026, 7, 28),
      '28.07.2026 14:30': DateTime(2026, 7, 28, 14, 30),
      '28/07/2026': DateTime(2026, 7, 28),
      '2026-07-28': DateTime(2026, 7, 28),
      '28.07.26': DateTime(2026, 7, 28), // двузначный год (Jusan/БЦК)
    };
    cases.forEach((input, expected) {
      test('«$input» распознаётся', () {
        final r = KaspiParser.parseCsv(csv('Дата;Описание;Сумма\n'
            '$input;Оплата;50 000\n'));
        expect(r.rows, isNotEmpty, reason: 'дата «$input» не распознана');
        expect(r.rows.first.date.year, expected.year);
        expect(r.rows.first.date.month, expected.month);
        expect(r.rows.first.date.day, expected.day);
      });
    });

    test('текстовый месяц «12 июля 2026»', () {
      final r = KaspiParser.parseCsv(
          csv('Дата;Описание;Сумма\n12 июля 2026;Оплата;50 000\n'));
      expect(r.rows, isNotEmpty);
      expect(r.rows.first.date.month, 7);
      expect(r.rows.first.date.day, 12);
    });
  });

  group('Суммы: пробелы, валюта, знаки', () {
    final cases = {
      '1 500,50': 1500.5,
      '1500.50': 1500.5,
      '1 500 ₸': 1500.0,
      '1500 KZT': 1500.0,
      '12 345,67 тг': 12345.67,
    };
    cases.forEach((input, expected) {
      test('«$input» → $expected', () {
        final r = KaspiParser.parseCsv(
            csv('Дата;Описание;Сумма\n01.07.2026;Оплата;$input\n'));
        expect(r.rows, isNotEmpty, reason: 'сумма «$input» не распознана');
        expect(r.rows.first.amount, closeTo(expected, 0.001));
      });
    });

    test('скобки = расход', () {
      final r = KaspiParser.parseCsv(
          csv('Дата;Описание;Сумма\n01.07.2026;Аренда;(30 000)\n'));
      expect(r.rows.first.isIncome, isFalse);
      expect(r.rows.first.amount, closeTo(30000, 0.001));
    });
  });

  group('Форматы банков', () {
    test('Kaspi Business: дебет/кредит', () {
      final r = KaspiParser.parseCsv(csv('Дата;Описание;Дебет;Кредит\n'
          '01.07.2026;Оплата от клиента;;50 000\n'
          '02.07.2026;Аренда офиса;30 000;\n'));
      expect(r.rows.length, 2);
      expect(r.rows[0].isIncome, isTrue);
      expect(r.rows[1].isIncome, isFalse);
    });

    test('Halyk: одна колонка «Сумма» со знаком', () {
      final r = KaspiParser.parseCsv(csv('Дата операции;Назначение платежа;Сумма\n'
          '01.07.2026;Оплата;50 000\n'
          '02.07.2026;Аренда;-30 000\n'));
      expect(r.rows.length, 2);
      expect(r.rows[0].isIncome, isTrue);
      expect(r.rows[1].isIncome, isFalse);
    });

    test('Jusan: только колонка «Списание» → расход', () {
      final r = KaspiParser.parseCsv(csv('Дата проводки;Получатель;Списание\n'
          '01.07.2026;ТОО Поставщик;30 000\n'));
      expect(r.rows, isNotEmpty);
      expect(r.rows.first.isIncome, isFalse);
    });

    test('БЦК: только колонка «Поступление» → доход', () {
      final r = KaspiParser.parseCsv(csv('Дата;Отправитель;Поступление\n'
          '01.07.2026;ИП Клиент;50 000\n'));
      expect(r.rows, isNotEmpty);
      expect(r.rows.first.isIncome, isTrue);
    });

    test('Forte: сокращения Дт/Кт', () {
      final r = KaspiParser.parseCsv(csv('Дата;Контрагент;Дт;Кт\n'
          '01.07.2026;ТОО Х;;50 000\n'));
      expect(r.rows, isNotEmpty);
      expect(r.rows.first.isIncome, isTrue);
    });

    test('склонения: «Сумма списания» / «Сумма поступления»', () {
      // Регрессия: словари хранят корни («списан»), иначе contains не ловит
      // склонённые формы и обе колонки уходят в «Сумму».
      final r = KaspiParser.parseCsv(
          csv('Дата;Контрагент;Сумма списания;Сумма поступления\n'
              '01.07.2026;ИП Клиент;;50 000\n'
              '02.07.2026;ТОО Поставщик;30 000;\n'));
      expect(r.rows.length, 2);
      expect(r.rows[0].isIncome, isTrue);
      expect(r.rows[1].isIncome, isFalse);
      expect(r.rows[1].amount, closeTo(30000, 0.001));
    });

    test('казахские заголовки', () {
      final r = KaspiParser.parseCsv(
          csv('Күні;Сипаттама;Сомасы\n01.07.2026;Төлем;50 000\n'));
      expect(r.rows, isNotEmpty);
    });

    test('английские заголовки', () {
      final r = KaspiParser.parseCsv(
          csv('Date;Description;Amount\n01.07.2026;Payment;50 000\n'));
      expect(r.rows, isNotEmpty);
    });
  });

  group('Устойчивость', () {
    test('«фактура» не принимается за кредит', () {
      // Если бы короткое «кт» матчилось подстрокой, колонка «Фактура»
      // стала бы колонкой кредита и суммы читались бы из неё.
      final r = KaspiParser.parseCsv(csv('Дата;Фактура;Сумма\n'
          '01.07.2026;Ф-123;50 000\n'));
      expect(r.rows, isNotEmpty);
      expect(r.rows.first.amount, closeTo(50000, 0.001));
    });

    test('шапка ниже строк-заголовков файла', () {
      final r = KaspiParser.parseCsv(csv('Выписка по счёту\n'
          'ИП Иванов, KZ123\n'
          'за период 01.07-31.07\n'
          '\n'
          'Дата;Описание;Сумма\n'
          '01.07.2026;Оплата;50 000\n'));
      expect(r.rows, isNotEmpty);
    });

    test('PDF отклоняется с понятной подсказкой', () {
      final r = KaspiParser.parseFile(csv('%PDF-1.4 fake'), 'vypiska.pdf');
      expect(r.rows, isEmpty);
      expect(r.format, 'pdf');
      expect(r.warnings.first, contains('Excel'));
    });

    test('нераспознанный файл отдаёт matrix для ручной разметки', () {
      final r = KaspiParser.parseCsv(csv('колонка1;колонка2\n'
          'мусор;ещё мусор\n'
          'текст;текст\n'));
      expect(r.rows, isEmpty);
      expect(r.canMapManually, isTrue,
          reason: 'должны предложить ручное сопоставление колонок');
    });
  });

  group('Ручное сопоставление колонок', () {
    test('нестандартный файл читается по указанным колонкам', () {
      // Заголовки, которых нет ни в одном словаре
      final parsed = KaspiParser.parseCsv(csv('Когда;Кому;Ушло;Пришло\n'
          '01.07.2026;ТОО Х;30 000;\n'
          '02.07.2026;ИП Y;;50 000\n'));
      expect(parsed.rows, isEmpty, reason: 'авто-разбор тут не должен сработать');

      final manual = KaspiParser.parseWithMapping(
        parsed.matrix,
        dateCol: 0,
        debitCol: 2,
        creditCol: 3,
        descCol: 1,
        headerRow: 0,
      );
      expect(manual.rows.length, 2);
      expect(manual.rows[0].isIncome, isFalse);
      expect(manual.rows[1].isIncome, isTrue);
    });

    test('без колонки суммы возвращает подсказку', () {
      final r = KaspiParser.parseWithMapping(
        [
          ['a', 'b'],
          ['01.07.2026', 'x']
        ],
        dateCol: 0,
      );
      expect(r.rows, isEmpty);
      expect(r.warnings.first, contains('сумм'));
    });
  });
}
