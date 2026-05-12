// Тесты на генерацию ЭСФ XML.
// Запуск: flutter test test/esf_service_test.dart
//
// Параллельно — образцы XML в samples/esf/ генерируются через
// `node samples/esf/_generate.js` и валидируются `python samples/esf/_validate.py`.

import 'package:flutter_test/flutter_test.dart';
import 'package:esep/core/models/invoice.dart';
import 'package:esep/core/providers/company_provider.dart';
import 'package:esep/core/services/esf_service.dart';

void main() {
  // ────────────────────────────────────────────────────────────────────────
  // Fixtures
  // ────────────────────────────────────────────────────────────────────────
  final fixedDate = DateTime(2026, 5, 12);

  CompanyInfo companyComplete({bool isVatPayer = false}) => CompanyInfo(
        name: 'ИП Алибеков А.К.',
        iin: '900101300123',
        address: 'г. Астана, пр. Кабанбай батыра, 11',
        bankName: 'Kaspi Bank',
        iik: 'KZ123456789012345678',
        bik: 'CASPKZKA',
        kbe: '19',
        isVatPayer: isVatPayer,
      );

  Invoice invoice({String? buyerIin = '060540001234'}) => Invoice(
        id: 'test-1',
        number: 'СЧ-2026-001',
        clientName: 'ТОО АстанаТрейд',
        buyerIin: buyerIin,
        items: [
          const InvoiceItem(
            id: 'item-1',
            description: 'Консультация по форме 910',
            quantity: 1,
            unitPrice: 50000,
            unitCode: '931',
            unitName: 'услуга',
          ),
          const InvoiceItem(
            id: 'item-2',
            description: 'Настройка учёта',
            quantity: 2,
            unitPrice: 25000,
            unitCode: '356',
            unitName: 'час',
          ),
        ],
        status: InvoiceStatus.draft,
        createdAt: fixedDate,
      );

  // ────────────────────────────────────────────────────────────────────────
  // Validation
  // ────────────────────────────────────────────────────────────────────────
  group('EsfService.validate', () {
    test('полные данные → isValid', () {
      final v = EsfService.validate(invoice(), companyComplete());
      expect(v.isValid, isTrue);
      expect(v.errors, isEmpty);
    });

    test('пустой ИИН покупателя → warning, не error', () {
      final v = EsfService.validate(
        invoice(buyerIin: null),
        companyComplete(),
      );
      expect(v.isValid, isTrue, reason: 'warnings не блокируют');
      expect(v.errors, isEmpty);
      expect(v.warnings, isNotEmpty);
      expect(v.warnings.first, contains('ИИН/БИН покупателя'));
    });

    test('ИИН покупателя длиной не 12 → error', () {
      final v = EsfService.validate(
        invoice(buyerIin: '12345'),
        companyComplete(),
      );
      expect(v.isValid, isFalse);
      expect(v.errors.any((e) => e.contains('12 цифр')), isTrue);
    });

    test('пустое название поставщика → error', () {
      final v = EsfService.validate(
        invoice(),
        const CompanyInfo(name: '', iin: '900101300123'),
      );
      expect(v.isValid, isFalse);
      expect(v.errors.any((e) => e.contains('название')), isTrue);
    });

    test('пустые позиции → error', () {
      final inv = Invoice(
        id: 'empty',
        number: 'СЧ-2026-002',
        clientName: 'ТОО Тест',
        buyerIin: '060540001234',
        items: const [],
        status: InvoiceStatus.draft,
        createdAt: fixedDate,
      );
      final v = EsfService.validate(inv, companyComplete());
      expect(v.isValid, isFalse);
      expect(v.errors.any((e) => e.contains('позиции')), isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Generation — non-VAT
  // ────────────────────────────────────────────────────────────────────────
  group('EsfService.generate (без НДС)', () {
    test('базовая структура валидна', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<ESF'));
      expect(xml, contains('</ESF>'));
      expect(xml, contains('<INVOICE_NUM>ЭСФ-2026-001</INVOICE_NUM>'));
    });

    test('без НДС: NDS_RATE=WITHOUT_NDS, NDS_SUM=0', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, contains('<NDS_RATE>WITHOUT_NDS</NDS_RATE>'));
      expect(xml, contains('<TOTAL_NDS>0.00</TOTAL_NDS>'));
      expect(xml, contains('<IS_VAT_PAYER>false</IS_VAT_PAYER>'));
      // Сумма = 50000 * 1 + 25000 * 2 = 100000
      expect(xml, contains('<TOTAL_NET_TURNOVER>100000.00</TOTAL_NET_TURNOVER>'));
      expect(xml, contains('<TOTAL_TURNOVER_WITH_NDS>100000.00</TOTAL_TURNOVER_WITH_NDS>'));
    });

    test('XML не содержит вложенных комментариев (не сломает парсер)', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      // Эвристика: внутри <!-- ... --> не должно быть второго <!-- или -->
      final headerCommentMatch = RegExp(r'<!--([\s\S]*?)-->').firstMatch(xml);
      expect(headerCommentMatch, isNotNull);
      final inside = headerCommentMatch!.group(1)!;
      expect(inside.contains('<!--'), isFalse,
          reason: 'Вложенный комментарий — невалидный XML');
      expect(inside.contains('-->'), isFalse,
          reason: 'Преждевременный конец комментария — невалидный XML');
    });

    test('ИИН покупателя попадает в XML', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, contains('<IIN_BIN>060540001234</IIN_BIN>'));
    });

    test('пустой ИИН покупателя → плейсхолдер-комментарий', () {
      final xml = EsfService.generate(
        invoice(buyerIin: null),
        companyComplete(),
      );
      expect(xml.contains('<IIN_BIN>'), isFalse);
      expect(xml, contains('ИИН/БИН покупателя не заполнен'));
    });

    test('UNIT_CODE/UNIT_NAME из позиции', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, contains('<UNIT_CODE>931</UNIT_CODE>'));
      expect(xml, contains('<UNIT_NAME>услуга</UNIT_NAME>'));
      expect(xml, contains('<UNIT_CODE>356</UNIT_CODE>'));
      expect(xml, contains('<UNIT_NAME>час</UNIT_NAME>'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Generation — VAT
  // ────────────────────────────────────────────────────────────────────────
  group('EsfService.generate (плательщик НДС)', () {
    test('NDS_RATE=NDS_16 на всех позициях', () {
      final xml = EsfService.generate(
        invoice(),
        companyComplete(isVatPayer: true),
      );
      // Должно быть 2 позиции с NDS_16
      final ndsMatches = RegExp('<NDS_RATE>NDS_16</NDS_RATE>').allMatches(xml);
      expect(ndsMatches.length, 2);
      expect(xml, contains('<IS_VAT_PAYER>true</IS_VAT_PAYER>'));
    });

    test('НДС 16% считается корректно', () {
      final xml = EsfService.generate(
        invoice(),
        companyComplete(isVatPayer: true),
      );
      // 50000 → 8000 НДС, 50000 (25000*2) → 8000 НДС, итого 16 000
      expect(xml, contains('<TOTAL_NET_TURNOVER>100000.00</TOTAL_NET_TURNOVER>'));
      expect(xml, contains('<TOTAL_NDS>16000.00</TOTAL_NDS>'));
      expect(xml, contains('<TOTAL_TURNOVER_WITH_NDS>116000.00</TOTAL_TURNOVER_WITH_NDS>'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // XML escaping
  // ────────────────────────────────────────────────────────────────────────
  group('XML экранирование', () {
    test('амперсанд и угловые скобки в названии не ломают XML', () {
      final inv = invoice().copyWith(clientName: 'ТОО "Тест & Co" <ИП>');
      final xml = EsfService.generate(inv, companyComplete());
      expect(xml.contains('ТОО "Тест & Co"'), isFalse);
      expect(xml, contains('&amp;'));
      expect(xml, contains('&lt;'));
      expect(xml, contains('&gt;'));
      expect(xml, contains('&quot;'));
    });
  });
}
