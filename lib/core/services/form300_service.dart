import 'dart:convert';
import 'dart:math';

import '../constants/kz_tax_constants.dart';
import 'file_saver.dart';

/// ─── Форма 300.00 — Декларация по НДС ───────────────────────────────────────
///
/// Версия 29, ревизия 170 (схема КГД form_300_00_v29_r170).
/// Период действия: 2023-2026. Квартальная, до 15 числа 2-го месяца
/// после отчётного квартала.
///
/// С 1 января 2026 ставка НДС = 16%.
///
/// Маппинг строк (из hint-текстов официальной схемы):
///   300.00.006 = общая сумма оборота по реализации
///   300.00.012 = всего начислено НДС (output)
///   300.00.021 = общая сумма оборота по приобретению
///   300.00.023 = НДС, относимый в зачёт (input)
///   300.00.030 I  = НДС к уплате в бюджет
///   300.00.030 II = превышение зачёта (к возврату/переносу)
///
/// MVP: базовый расчёт output − input. Приложения (нулевая ставка, импорт,
/// освобождённые обороты, пропорциональный зачёт) — в roadmap.

enum Form300Format { xmlSono, jsonIsna }

extension Form300FormatExt on Form300Format {
  String get ext => this == Form300Format.xmlSono ? 'xml' : 'json';
  String get label =>
      this == Form300Format.xmlSono ? 'XML — СОНО' : 'JSON — КНП ИСНА';
}

class Form300Data {
  final String iin;
  final String fullName;
  final int year;
  final int quarter;
  final String declarationType;

  /// Облагаемый оборот по реализации (без НДС), ₸
  final double salesTurnover;

  /// Оборот по приобретению с НДС в зачёт (без НДС), ₸
  final double purchaseTurnover;

  final double vatRate;

  const Form300Data({
    required this.iin,
    required this.fullName,
    required this.year,
    required this.quarter,
    required this.declarationType,
    required this.salesTurnover,
    required this.purchaseTurnover,
    required this.vatRate,
  });

  /// Начисленный НДС (output) — строка 300.00.012
  double get outputVat => _round(salesTurnover * vatRate);

  /// НДС в зачёт (input) — строка 300.00.023
  double get inputVat => _round(purchaseTurnover * vatRate);

  /// К уплате в бюджет — строка 300.00.030 I (если output > input)
  double get vatPayable => max(0.0, _round(outputVat - inputVat));

  /// Превышение зачёта — строка 300.00.030 II (если input > output)
  double get vatExcess => max(0.0, _round(inputVat - outputVat));

  String get periodLabel => '$quarter квартал $year';

  static double _round(double v) => (v * 100).round() / 100;
}

class Form300Service {
  static const _formCode = '300.00';
  static const _formVersion = '29';
  static const _formRevision = '170';

  /// Расчёт формы 300.
  /// [withVat] — true если введённые суммы уже включают НДС (тогда выделяем
  /// НДС изнутри: сумма × ставка/(1+ставка)). false — суммы без НДС (НДС сверху).
  static Form300Data calculate({
    required String iin,
    required String fullName,
    required int year,
    required int quarter,
    required double salesAmount,
    required double purchaseAmount,
    bool amountsIncludeVat = false,
    double? vatRate,
    String declarationType = 'main',
  }) {
    final rate = vatRate ?? KzTax.vatRate; // 16%
    double netSales = salesAmount;
    double netPurchase = purchaseAmount;
    if (amountsIncludeVat) {
      // Выделяем оборот без НДС из суммы с НДС
      netSales = salesAmount / (1 + rate);
      netPurchase = purchaseAmount / (1 + rate);
    }
    return Form300Data(
      iin: iin,
      fullName: fullName,
      year: year,
      quarter: quarter,
      declarationType: declarationType,
      salesTurnover: (netSales * 100).round() / 100,
      purchaseTurnover: (netPurchase * 100).round() / 100,
      vatRate: rate,
    );
  }

  static Map<String, double> _fieldValues(Form300Data d) {
    return {
      'field_300_00_006': d.salesTurnover, // оборот реализации
      'field_300_00_012': d.outputVat, // начислено НДС
      'field_300_00_021': d.purchaseTurnover, // оборот приобретения
      'field_300_00_023': d.inputVat, // НДС в зачёт
      'field_300_00_030_01': d.vatPayable, // к уплате
      'field_300_00_030_02': d.vatExcess, // превышение зачёта
    };
  }

  static String _declarationTypeField(Form300Data d) {
    switch (d.declarationType) {
      case 'regular':
        return 'dt_regular';
      case 'additional':
        return 'dt_additional';
      case 'final':
        return 'dt_final';
      default:
        return 'dt_main';
    }
  }

  static String generate(Form300Data data, Form300Format format) =>
      format == Form300Format.xmlSono
          ? generateXml(data)
          : generateJson(data);

  static String generateXml(Form300Data data) {
    final fields = _fieldValues(data);
    final dtField = _declarationTypeField(data);
    final fieldXml = fields.entries
        .map((e) => '  <${e.key}>${e.value.toStringAsFixed(2)}</${e.key}>')
        .join('\n');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!--
  Форма 300.00 (версия $_formVersion, ревизия $_formRevision) — сгенерирована Esep.
  Имена полей — из официального пакета КГД form_300_00_v29_r170.
  MVP: базовый расчёт НДС output − input по ставке ${(data.vatRate * 100).toStringAsFixed(0)}%.
  Приложения (0%, импорт, освобождённые) не включены — ПЕРЕД ПОДАЧЕЙ
  сверить с экспортом из 1С/СОНО и при необходимости дозаполнить.
-->
<form code="$_formCode" version="$_formVersion" revision="$_formRevision">
  <iin>${_escapeXml(data.iin)}</iin>
  <payer_name1>${_escapeXml(data.fullName)}</payer_name1>
  <period_year>${data.year}</period_year>
  <period_quarter>${data.quarter}</period_quarter>
  <$dtField>1</$dtField>
  <currency_code>KZT</currency_code>
$fieldXml
</form>''';
  }

  static String generateJson(Form300Data data) {
    final payload = {
      '_meta': {
        'generatedBy': 'Esep',
        'generatedAt': DateTime.now().toIso8601String(),
        'note': 'MVP базовый расчёт НДС. Приложения (0%, импорт, '
            'освобождённые обороты) не включены. Сверить с 1С.',
      },
      'formCode': _formCode,
      'version': _formVersion,
      'revision': _formRevision,
      'period': {'year': data.year, 'quarter': data.quarter},
      'taxpayer': {'iin': data.iin, 'name': data.fullName},
      'declarationType': _declarationTypeField(data),
      'vatRate': data.vatRate,
      'currencyCode': 'KZT',
      'summary': {
        'salesTurnover': data.salesTurnover,
        'outputVat': data.outputVat,
        'purchaseTurnover': data.purchaseTurnover,
        'inputVat': data.inputVat,
        'vatPayable': data.vatPayable,
        'vatExcess': data.vatExcess,
      },
      'fields': {
        for (final e in _fieldValues(data).entries)
          e.key: double.parse(e.value.toStringAsFixed(2)),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static Future<void> shareFile(Form300Data data, Form300Format format) async {
    final content = generate(data, format);
    final fileName = 'form_300_${data.year}_Q${data.quarter}.${format.ext}';
    final bytes = utf8.encode(content);
    await saveAndShareFile(bytes, fileName,
        subject: 'Форма 300.00 — ${data.periodLabel} (${format.label})');
  }

  static String _escapeXml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
