// Тесты на генерацию ЭСФ XML в формате контейнера импорта ИС ЭСФ
// (esf:invoiceInfoContainer → invoiceBody CDATA → v2:invoice).
//
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
        operatorFullname: 'Алибеков Аскар Канатович',
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
            esfUnitCode: '5114',
          ),
          const InvoiceItem(
            id: 'item-2',
            description: 'Настройка учёта',
            quantity: 2,
            unitPrice: 25000,
            unitCode: '356',
            unitName: 'час',
            esfUnitCode: '5114',
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

    test('пустое ФИО оператора → error', () {
      final v = EsfService.validate(
        invoice(),
        const CompanyInfo(name: 'ИП Тест', iin: '900101300123'),
      );
      expect(v.isValid, isFalse);
      expect(v.errors.any((e) => e.contains('ФИО оператора')), isTrue);
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

    test('грузоотправитель не совпадает, но не заполнен → error', () {
      final inv = invoice().copyWith(consignorSameAsSeller: false);
      final v = EsfService.validate(inv, companyComplete());
      expect(v.isValid, isFalse);
      expect(v.errors.any((e) => e.contains('грузоотправителя')), isTrue);
    });

    test('позиция без кода ед. ЭСФ → warning', () {
      final inv = invoice().copyWith(items: [
        const InvoiceItem(
          id: 'x',
          description: 'Без кода',
          quantity: 1,
          unitPrice: 1000,
        ),
      ]);
      final v = EsfService.validate(inv, companyComplete());
      expect(v.isValid, isTrue);
      expect(v.warnings.any((w) => w.contains('код единицы измерения')), isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Структура контейнера
  // ────────────────────────────────────────────────────────────────────────
  group('EsfService.generate — структура контейнера', () {
    test('контейнер invoiceInfoContainer с CDATA-телом', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<esf:invoiceInfoContainer xmlns:esf="esf">'));
      expect(xml, contains('<invoiceBody><![CDATA['));
      expect(xml, contains('</v2:invoice>]]></invoiceBody>'));
      expect(xml, contains('</esf:invoiceInfoContainer>'));
    });

    test('внутренний документ v2:invoice с нужными namespace', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(
        xml,
        contains('<v2:invoice xmlns:a="abstractInvoice.esf" xmlns:v2="v2.esf">'),
      );
      expect(xml, contains('<invoiceType>ORDINARY_INVOICE</invoiceType>'));
      expect(xml, contains('<num>СЧ-2026-001</num>'));
      expect(xml, contains('<date>12.05.2026</date>'));
      expect(xml, contains('<turnoverDate>12.05.2026</turnoverDate>'));
    });

    test('системные поля не выводятся', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml.contains('<invoiceId>'), isFalse);
      expect(xml.contains('<registrationNumber>'), isFalse);
      expect(xml.contains('<signature>'), isFalse);
      expect(xml.contains('<certificate>'), isFalse);
      expect(xml.contains('<invoiceStatus>'), isFalse);
    });

    test('ФИО оператора попадает в XML', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(
        xml,
        contains('<operatorFullname>Алибеков Аскар Канатович</operatorFullname>'),
      );
    });

    test('поставщик и покупатель в правильных секциях', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, contains('<tin>900101300123</tin>')); // продавец
      expect(xml, contains('<tin>060540001234</tin>')); // покупатель
      expect(xml, contains('<name>ТОО АстанаТрейд</name>'));
      expect(xml, contains('<bik>CASPKZKA</bik>'));
      expect(xml, contains('<iik>KZ123456789012345678</iik>'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Generation — non-VAT
  // ────────────────────────────────────────────────────────────────────────
  group('EsfService.generate (без НДС)', () {
    test('без НДС: ndsAmount=0, суммы равны', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      // Сумма = 50000 * 1 + 25000 * 2 = 100000
      expect(xml, contains('<totalNdsAmount>0</totalNdsAmount>'));
      expect(xml, contains('<totalPriceWithoutTax>100000</totalPriceWithoutTax>'));
      expect(xml, contains('<totalPriceWithTax>100000</totalPriceWithTax>'));
      expect(xml, contains('<totalTurnoverSize>100000</totalTurnoverSize>'));
      expect(xml, contains('<totalExciseAmount>0</totalExciseAmount>'));
    });

    test('код единицы измерения ЭСФ выводится в unitNomenclature', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      final matches =
          RegExp('<unitNomenclature>5114</unitNomenclature>').allMatches(xml);
      expect(matches.length, 2);
    });

    test('позиция без кода ед. ЭСФ → тег unitNomenclature отсутствует', () {
      final inv = invoice().copyWith(items: [
        const InvoiceItem(
          id: 'x',
          description: 'Без кода',
          quantity: 1,
          unitPrice: 1000,
        ),
      ]);
      final xml = EsfService.generate(inv, companyComplete());
      expect(xml.contains('<unitNomenclature>'), isFalse);
    });

    test('catalogTruId и truOriginCode имеют дефолты', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, contains('<catalogTruId>1</catalogTruId>'));
      expect(xml, contains('<truOriginCode>5</truOriginCode>'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Generation — VAT
  // ────────────────────────────────────────────────────────────────────────
  group('EsfService.generate (плательщик НДС)', () {
    test('НДС 16% считается корректно', () {
      final xml = EsfService.generate(
        invoice(),
        companyComplete(isVatPayer: true),
      );
      // 50000 → 8000 НДС, 50000 (25000*2) → 8000 НДС, итого 16 000
      expect(xml, contains('<totalPriceWithoutTax>100000</totalPriceWithoutTax>'));
      expect(xml, contains('<totalNdsAmount>16000</totalNdsAmount>'));
      expect(xml, contains('<totalPriceWithTax>116000</totalPriceWithTax>'));
    });

    test('ndsAmount проставлен на каждой позиции', () {
      final xml = EsfService.generate(
        invoice(),
        companyComplete(isVatPayer: true),
      );
      final matches = RegExp('<ndsAmount>8000</ndsAmount>').allMatches(xml);
      expect(matches.length, 2);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Форматирование чисел
  // ────────────────────────────────────────────────────────────────────────
  group('Форматирование чисел', () {
    test('хвостовые нули обрезаются, дробная часть сохраняется', () {
      final inv = invoice().copyWith(items: [
        const InvoiceItem(
          id: 'frac',
          description: 'Услуга с дробной ценой',
          quantity: 1,
          unitPrice: 1335906.5,
          esfUnitCode: '5114',
        ),
      ]);
      final xml = EsfService.generate(inv, companyComplete());
      expect(xml, contains('<unitPrice>1335906.5</unitPrice>'));
      expect(xml, contains('<priceWithoutTax>1335906.5</priceWithoutTax>'));
      expect(xml.contains('1335906.50'), isFalse);
    });

    test('целые числа без десятичной точки', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, contains('<quantity>1</quantity>'));
      expect(xml, contains('<quantity>2</quantity>'));
      expect(xml.contains('<quantity>1.00</quantity>'), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Грузоотправитель / грузополучатель
  // ────────────────────────────────────────────────────────────────────────
  group('Грузоотправитель / грузополучатель', () {
    test('по умолчанию consignor = поставщик, consignee = покупатель', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      // consignor берёт ИИН поставщика, consignee — ИИН покупателя
      expect(xml, contains('<consignor>'));
      expect(xml, contains('<consignee>'));
      // имя поставщика встречается и в consignor, и в sellers
      final sellerNameMatches =
          RegExp('<name>ИП Алибеков А.К.</name>').allMatches(xml);
      expect(sellerNameMatches.length, 2);
    });

    test('отдельный грузоотправитель выводится из полей счёта', () {
      final inv = invoice().copyWith(
        consignorSameAsSeller: false,
        consignorName: 'ТОО Склад-Логистик',
        consignorTin: '111111111111',
        consignorAddress: 'г. Алматы, ул. Складская 1',
      );
      final xml = EsfService.generate(inv, companyComplete());
      expect(xml, contains('<name>ТОО Склад-Логистик</name>'));
      expect(xml, contains('<tin>111111111111</tin>'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Договор-основание
  // ────────────────────────────────────────────────────────────────────────
  group('Договор-основание', () {
    test('без договора → hasContract=false', () {
      final xml = EsfService.generate(invoice(), companyComplete());
      expect(xml, contains('<hasContract>false</hasContract>'));
    });

    test('с договором → hasContract=true + номер и дата', () {
      final inv = invoice().copyWith(
        contractNum: '994919/2024/1',
        contractDate: DateTime(2024, 8, 27),
      );
      final xml = EsfService.generate(inv, companyComplete());
      expect(xml, contains('<hasContract>true</hasContract>'));
      expect(xml, contains('<contractNum>994919/2024/1</contractNum>'));
      expect(xml, contains('<contractDate>27.08.2024</contractDate>'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // XML escaping
  // ────────────────────────────────────────────────────────────────────────
  group('XML экранирование', () {
    test('амперсанд и угловые скобки в названии не ломают XML', () {
      final inv = invoice().copyWith(clientName: 'ТОО "Тест & Co" <ИП>');
      final xml = EsfService.generate(inv, companyComplete());
      expect(xml.contains('ТОО "Тест & Co" <ИП>'), isFalse);
      expect(xml, contains('&amp;'));
      expect(xml, contains('&lt;'));
      expect(xml, contains('&gt;'));
      expect(xml, contains('&quot;'));
    });
  });
}
