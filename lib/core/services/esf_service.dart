import 'package:intl/intl.dart';

import '../models/invoice.dart';
import '../providers/company_provider.dart';
import '../constants/kz_tax_constants.dart';

/// Результат валидации перед генерацией ЭСФ
class EsfValidation {
  /// Блокирующие ошибки — XML не должен генерироваться
  final List<String> errors;
  /// Предупреждения — XML генерируется, но клиента надо предупредить
  final List<String> warnings;

  const EsfValidation({this.errors = const [], this.warnings = const []});

  bool get isValid => errors.isEmpty;
  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;
}

/// Генератор ЭСФ XML для ИС ЭСФ КГД РК
/// Формат: IS ESF v9, тип — обычная счёт-фактура
class EsfService {
  EsfService._();

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _numFmt = NumberFormat('0.00', 'en_US');

  /// Проверка готовности данных для генерации ЭСФ.
  /// Используйте перед `generate()`.
  static EsfValidation validate(Invoice invoice, CompanyInfo company) {
    final errors = <String>[];
    final warnings = <String>[];

    // Данные поставщика
    if (company.name.isEmpty) {
      errors.add('Не заполнено название/ФИО поставщика (Настройки → Компания)');
    }
    if (company.iin.isEmpty) {
      errors.add('Не заполнен ИИН/БИН поставщика (Настройки → Компания)');
    } else if (company.iin.length != 12) {
      errors.add('ИИН/БИН поставщика должен содержать 12 цифр');
    }

    // Данные покупателя
    if (invoice.clientName.isEmpty) {
      errors.add('Не указано имя покупателя');
    }
    if (invoice.buyerIin == null || invoice.buyerIin!.isEmpty) {
      warnings.add(
          'ИИН/БИН покупателя не указан — ЭСФ не примет получатель-юрлицо. '
          'Заполните для отгрузки ИП/ТОО.');
    } else if (invoice.buyerIin!.length != 12) {
      errors.add('ИИН/БИН покупателя должен содержать 12 цифр');
    }

    // Позиции
    if (invoice.items.isEmpty) {
      errors.add('В счёте нет ни одной позиции');
    }

    // Банковские реквизиты — мягкое предупреждение
    if (company.iik == null || company.iik!.isEmpty) {
      warnings.add(
          'Не заполнен ИИК (IBAN) поставщика — покупатель не увидит реквизиты для оплаты.');
    }

    return EsfValidation(errors: errors, warnings: warnings);
  }

  /// Генерирует XML строку ЭСФ.
  /// Если `company.isVatPayer == true` — товары/услуги облагаются НДС 16%.
  /// Сумма строки трактуется как **без НДС** (net), НДС начисляется сверху.
  static String generate(Invoice invoice, CompanyInfo company) {
    final now = DateTime.now();
    final invoiceDate = _dateFmt.format(invoice.createdAt);
    final today = _dateFmt.format(now);
    final esfNumber = _toEsfNumber(invoice.number);
    final isVat = company.isVatPayer;
    final vatRate = KzTax.vatRate; // 0.16

    double totalNet = 0;
    double totalVat = 0;
    double totalGross = 0;

    final items = invoice.items.asMap().entries.map((e) {
      final i = e.key + 1;
      final item = e.value;
      final net = item.total;
      final vat = isVat ? net * vatRate : 0.0;
      final gross = net + vat;
      totalNet += net;
      totalVat += vat;
      totalGross += gross;

      return '''    <PRODUCT>
      <NUM>$i</NUM>
      <DESCRIPTION>${_esc(item.description)}</DESCRIPTION>
      <UNIT_CODE>${_esc(item.unitCode)}</UNIT_CODE>
      <UNIT_NAME>${_esc(item.unitName)}</UNIT_NAME>
      <COUNT>${_numFmt.format(item.quantity)}</COUNT>
      <PRICE>${_numFmt.format(item.unitPrice)}</PRICE>
      <NET_TURNOVER>${_numFmt.format(net)}</NET_TURNOVER>
      <NDS_RATE>${isVat ? 'NDS_16' : 'WITHOUT_NDS'}</NDS_RATE>
      <NDS_SUM>${_numFmt.format(vat)}</NDS_SUM>
      <TURNOVER_WITH_NDS>${_numFmt.format(gross)}</TURNOVER_WITH_NDS>
    </PRODUCT>''';
    }).join('\n');

    final buyerIin = invoice.buyerIin ?? '';
    final buyerIinNode = buyerIin.isNotEmpty
        ? '<IIN_BIN>${_esc(buyerIin)}</IIN_BIN>'
        : '<!-- ИИН/БИН покупателя не заполнен — заполните перед загрузкой на esf.gov.kz -->';

    final vatNotice = isVat
        ? 'Поставщик является плательщиком НДС: ставка 16% по НК РК 2026'
        : 'Поставщик не является плательщиком НДС (СНР/упрощёнка)';

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!--
  ЭСФ сгенерирован приложением Esep (esep.kz)
  Для загрузки перейдите: https://esf.gov.kz
  Дата генерации: $today
  $vatNotice
-->
<ESF xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

  <!-- 1. Заголовок -->
  <HEADER>
    <INVOICE_NUM>$esfNumber</INVOICE_NUM>
    <INVOICE_DATE>$invoiceDate</INVOICE_DATE>
    <DELIVERY_DATE>$invoiceDate</DELIVERY_DATE>
    <TYPE>ORDINARY</TYPE>
    <CORRECTION>false</CORRECTION>
    <INPUT_TYPE>MANUAL</INPUT_TYPE>
  </HEADER>

  <!-- 2. Поставщик -->
  <SELLER>
    <IIN>${_esc(company.iin)}</IIN>
    <NAME>${_esc(company.name)}</NAME>
    <ADDRESS>${_esc(company.address ?? '')}</ADDRESS>
    <IS_VAT_PAYER>${isVat ? 'true' : 'false'}</IS_VAT_PAYER>
${company.iik != null && company.iik!.isNotEmpty ? '''    <BANK_DETAILS>
      <NAME>${_esc(company.bankName ?? '')}</NAME>
      <IIK>${_esc(company.iik ?? '')}</IIK>
      <BIK>${_esc(company.bik ?? '')}</BIK>
      <KBE>${_esc(company.kbe ?? '19')}</KBE>
    </BANK_DETAILS>''' : '    <!-- Банковские реквизиты не заполнены -->'}
  </SELLER>

  <!-- 3. Получатель -->
  <BUYER>
    $buyerIinNode
    <NAME>${_esc(invoice.clientName)}</NAME>
  </BUYER>

  <!-- 4. Оборот -->
  <TURNOVER>
$items
  </TURNOVER>

  <!-- 5. Итого -->
  <TOTAL>
    <TOTAL_NET_TURNOVER>${_numFmt.format(totalNet)}</TOTAL_NET_TURNOVER>
    <TOTAL_NDS>${_numFmt.format(totalVat)}</TOTAL_NDS>
    <TOTAL_TURNOVER_WITH_NDS>${_numFmt.format(totalGross)}</TOTAL_TURNOVER_WITH_NDS>
  </TOTAL>

  <!--
    ВАЖНО: Перед отправкой в ИС ЭСФ:
    1. Убедитесь что ИИН/БИН покупателя заполнен (12 цифр)
    2. Подпишите файл ЭЦП (НУЦ РК) в портале esf.gov.kz
    3. Или загрузите XML вручную через импорт
  -->

</ESF>''';
  }

  /// СЧ-2026-001 → ЭСФ-2026-001
  static String _toEsfNumber(String invoiceNumber) {
    return invoiceNumber.replaceFirst('СЧ-', 'ЭСФ-');
  }

  /// XML-экранирование спецсимволов
  static String _esc(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
