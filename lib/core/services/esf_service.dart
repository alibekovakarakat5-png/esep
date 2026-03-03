import 'package:intl/intl.dart';

import '../models/invoice.dart';
import '../providers/company_provider.dart';

/// Генератор ЭСФ XML для ИС ЭСФ КГД РК
/// Формат: IS ESF v9, тип — обычная счёт-фактура
class EsfService {
  EsfService._();

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _numFmt = NumberFormat('0.00', 'en_US');

  /// Генерирует XML строку ЭСФ
  static String generate(Invoice invoice, CompanyInfo company) {
    final now = DateTime.now();
    final invoiceDate = _dateFmt.format(invoice.createdAt);
    final today = _dateFmt.format(now);
    final total = invoice.totalAmount;
    final esfNumber = _toEsfNumber(invoice.number);

    final items = invoice.items.asMap().entries.map((e) {
      final i = e.key + 1;
      final item = e.value;
      return '''    <PRODUCT>
      <NUM>$i</NUM>
      <DESCRIPTION>${_esc(item.description)}</DESCRIPTION>
      <UNIT_CODE>796</UNIT_CODE>
      <UNIT_NAME>штука</UNIT_NAME>
      <COUNT>${_numFmt.format(item.quantity)}</COUNT>
      <PRICE>${_numFmt.format(item.unitPrice)}</PRICE>
      <NET_TURNOVER>${_numFmt.format(item.total)}</NET_TURNOVER>
      <NDS_RATE>WITHOUT_NDS</NDS_RATE>
      <NDS_SUM>0.00</NDS_SUM>
      <TURNOVER_WITH_NDS>${_numFmt.format(item.total)}</TURNOVER_WITH_NDS>
    </PRODUCT>''';
    }).join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!--
  ЭСФ сгенерирован приложением Есеп (esep.kz)
  Для загрузки перейдите: https://esf.gov.kz
  Дата генерации: $today
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
${company.iik != null && company.iik!.isNotEmpty ? '''    <BANK_DETAILS>
      <NAME>${_esc(company.bankName ?? '')}</NAME>
      <IIK>${_esc(company.iik ?? '')}</IIK>
      <BIK>${_esc(company.bik ?? '')}</BIK>
      <KBE>${_esc(company.kbe ?? '19')}</KBE>
    </BANK_DETAILS>''' : '    <!-- Банковские реквизиты не заполнены -->'}
  </SELLER>

  <!-- 3. Получатель -->
  <BUYER>
    <IIN_BIN></IIN_BIN>
    <NAME>${_esc(invoice.clientName)}</NAME>
  </BUYER>

  <!-- 4. Оборот -->
  <TURNOVER>
$items
  </TURNOVER>

  <!-- 5. Итого -->
  <TOTAL>
    <TOTAL_NET_TURNOVER>${_numFmt.format(total)}</TOTAL_NET_TURNOVER>
    <TOTAL_NDS>0.00</TOTAL_NDS>
    <TOTAL_TURNOVER_WITH_NDS>${_numFmt.format(total)}</TOTAL_TURNOVER_WITH_NDS>
  </TOTAL>

  <!--
    ВАЖНО: Перед отправкой в ИС ЭСФ:
    1. Убедитесь что ИИН/БИН покупателя заполнен
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
