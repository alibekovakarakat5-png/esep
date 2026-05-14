import 'dart:convert';
import 'package:intl/intl.dart';

import 'file_saver.dart';

import '../models/transaction.dart';
import '../constants/kz_tax_constants.dart';
import '../providers/company_provider.dart';

/// Формат выгрузки формы 910.00.
///
/// - [xmlSono] — XML для старой системы СОНО (её сворачивают)
/// - [jsonIsna] — JSON для нового КНП ИСНА (актуальный формат на 2026)
enum Form910Format {
  xmlSono,
  jsonIsna;

  String get ext => this == Form910Format.xmlSono ? 'xml' : 'json';
  String get label => this == Form910Format.xmlSono
      ? 'XML (СОНО)'
      : 'JSON (КНП ИСНА)';
}

/// Данные формы 910.00 — Упрощённая декларация для субъектов малого бизнеса
class Form910Data {
  // Header
  final String iin;
  final String fullName;
  final int halfYear; // 1 или 2
  final int year;
  final String declarationType; // 'очередная', 'дополнительная', 'ликвидационная'

  // Section 1: Tax calculation
  final double income;                  // 910.00.001
  final double incomeNonCash;           // 910.00.001 A
  final double incomeEcommerce;         // 910.00.001 B
  final double transferPricing;         // 910.00.002
  final double avgEmployees;            // 910.00.003
  final double avgMonthlyWage;          // 910.00.004
  final double calculatedTax;           // 910.00.005 = income * 4%
  final double taxAdjustment;           // 910.00.006
  final double netTax;                  // 910.00.007 = 005 - 006
  final double ipn;                     // 910.00.008 = 007 (100% ИПН)
  final double socialTax;               // 910.00.009 = 0% для СНР с 2026

  // Section 2: Social contributions (за ИП "за себя")
  final double soIncome;                // 910.00.010
  final double soAmount;                // 910.00.011
  final double opvIncome;               // 910.00.012
  final double opvAmount;               // 910.00.013
  final double opvrAmount;              // 910.00.014
  final double vosmsAmount;             // 910.00.015

  const Form910Data({
    required this.iin,
    required this.fullName,
    required this.halfYear,
    required this.year,
    this.declarationType = 'очередная',
    required this.income,
    this.incomeNonCash = 0,
    this.incomeEcommerce = 0,
    this.transferPricing = 0,
    this.avgEmployees = 0,
    this.avgMonthlyWage = 0,
    required this.calculatedTax,
    this.taxAdjustment = 0,
    required this.netTax,
    required this.ipn,
    required this.socialTax,
    required this.soIncome,
    required this.soAmount,
    required this.opvIncome,
    required this.opvAmount,
    required this.opvrAmount,
    required this.vosmsAmount,
  });

  double get totalTax => ipn + socialTax;
  double get totalSocial => soAmount + opvAmount + opvrAmount + vosmsAmount;
  double get grandTotal => totalTax + totalSocial;

  String get periodLabel => halfYear == 1
      ? '1-е полугодие $year'
      : '2-е полугодие $year';
}

/// Генератор формы 910.00 (Упрощённая декларация).
///
/// ⚠️ ВАЖНО ПРО ФОРМАТЫ (проверено по kgd.gov.kz, pro1c.kz, uchet.kz):
/// - Имена полей (`field_910_00_001` и т.д.) — из официального пакета
///   СОНО v27 r133, см. `docs/forms/form-910-00-v27-spec.md`.
/// - Конверт XML (корневой элемент) и схема JSON ИСНА **публично не
///   опубликованы**. Реализованы по обоснованной догадке. Перед боевым
///   использованием обязательно сверить с реальным образцом экспорта
///   из 1С / КНП ИСНА.
/// - Реальная форма ждёт помесячную разбивку (поля `_1.._6`), а здесь
///   считаются 6-месячные агрегаты — месячные поля не заполняются.
class Form910Service {
  Form910Service._();

  static const _formCode = '910.00';
  static const _formVersion = 27;
  static const _formRevision = 133;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _amountFmt = NumberFormat('0.00', 'en_US');

  /// Calculate form 910 data from transactions
  static Form910Data calculate({
    required List<Transaction> transactions,
    required CompanyInfo company,
    required int halfYear,
    required int year,
    int employeeCount = 0,
    double totalPayroll = 0,
    bool bornBefore1975 = false,
  }) {
    // Filter transactions for the relevant half-year
    final startMonth = halfYear == 1 ? 1 : 7;
    final endMonth = halfYear == 1 ? 6 : 12;

    final relevantTxs = transactions.where((t) =>
        t.date.year == year &&
        t.date.month >= startMonth &&
        t.date.month <= endMonth).toList();

    final income = relevantTxs
        .where((t) => t.isIncome)
        .fold(0.0, (s, t) => s + t.amount);

    final incomeNonCash = relevantTxs
        .where((t) => t.isIncome && (t.source == 'kaspi' || t.source == 'перевод' || t.source == 'карта'))
        .fold(0.0, (s, t) => s + t.amount);

    // Tax calculation (Новый НК РК 2026, ставка 4%)
    final calculatedTax = income * KzTax.simplified910TotalRate; // 4%

    // Regional 2-6% adjustments are handled by the configured 910 rate.
    const taxAdjustment = 0.0;

    final netTax = calculatedTax - taxAdjustment;
    final ipn = netTax;

    // Social contributions for the half-year (6 months)
    final social = KzTax.calculateMonthlySocial(bornBefore1975: bornBefore1975);
    final soTotal = social.so * 6;

    // Social tax is 0% for special tax regimes under the 2026 config.
    const socialTax = 0.0;

    return Form910Data(
      iin: company.iin,
      fullName: company.name,
      halfYear: halfYear,
      year: year,
      income: income,
      incomeNonCash: incomeNonCash,
      avgEmployees: employeeCount.toDouble(),
      avgMonthlyWage: employeeCount > 0 ? totalPayroll / employeeCount : 0,
      calculatedTax: calculatedTax,
      taxAdjustment: taxAdjustment,
      netTax: netTax,
      ipn: ipn,
      socialTax: socialTax,
      soIncome: KzTax.currentMzp * 6,
      soAmount: soTotal,
      opvIncome: KzTax.currentMzp * 6,
      opvAmount: social.opv * 6,
      opvrAmount: social.opvr * 6,
      vosmsAmount: social.vosms * 6,
    );
  }

  /// Соответствие данных → официальные имена полей формы 910.00 v27.
  /// Источник имён: `docs/forms/form-910-00-v27-spec.md`.
  static Map<String, double> _fieldValues(Form910Data d) => {
        'field_910_00_001': d.income,
        'field_910_00_001_A': d.incomeNonCash,
        'field_910_00_001_B': d.incomeEcommerce,
        'field_910_00_002': d.transferPricing,
        'field_910_00_003': d.avgEmployees,
        'field_910_00_004': d.avgMonthlyWage,
        'field_910_00_005': d.calculatedTax,
        'field_910_00_006': d.taxAdjustment,
        'field_910_00_007': d.netTax,
        'field_910_00_008': d.ipn,
        'field_910_00_009': d.socialTax,
        'field_910_00_010': d.soIncome,
        'field_910_00_011': d.soAmount,
        'field_910_00_012': d.opvIncome,
        'field_910_00_013': d.opvAmount,
        'field_910_00_014': d.opvrAmount,
        'field_910_00_015': d.vosmsAmount,
      };

  /// Чекбокс типа декларации (dt_main / dt_additional / dt_final).
  static String _declarationTypeField(Form910Data d) {
    switch (d.declarationType) {
      case 'дополнительная':
        return 'dt_additional';
      case 'ликвидационная':
        return 'dt_final';
      default:
        return 'dt_main';
    }
  }

  /// Универсальная точка генерации — выбирает формат.
  static String generate(Form910Data data, Form910Format format) {
    return format == Form910Format.xmlSono
        ? generateXml(data)
        : generateJson(data);
  }

  /// XML для СОНО. Имена полей официальные, конверт — по догадке.
  static String generateXml(Form910Data data) {
    final fields = _fieldValues(data);
    final dtField = _declarationTypeField(data);
    final fieldXml = fields.entries
        .map((e) => '  <${e.key}>${_amountFmt.format(e.value)}</${e.key}>')
        .join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!--
  Форма 910.00 (версия $_formVersion, ревизия $_formRevision) — сгенерирована Esep.
  Имена полей — из официального пакета СОНО. Корневой конверт реализован
  по догадке: ПЕРЕД ПОДАЧЕЙ сверить с образцом экспорта из 1С/СОНО.
  Дата генерации: ${_dateFmt.format(DateTime.now())}
-->
<form code="$_formCode" version="$_formVersion" revision="$_formRevision">
  <iin>${_escapeXml(data.iin)}</iin>
  <payer_name1>${_escapeXml(data.fullName)}</payer_name1>
  <period_year>${data.year}</period_year>
  <period_half_year>${data.halfYear}</period_half_year>
  <$dtField>1</$dtField>
  <currency_code>KZT</currency_code>
$fieldXml
</form>''';
  }

  /// JSON для КНП ИСНА. ⚠️ Схема ИСНА публично не опубликована — структура
  /// реализована по обоснованной догадке, сверить с реальным образцом
  /// экспорта из 1С (команда «Экспорт в ИСНА (JSON)») или из КНП ИСНА.
  static String generateJson(Form910Data data) {
    final payload = {
      // ⚠️ unverified envelope — structure pending real ИСНА sample
      '_meta': {
        'generatedBy': 'Esep',
        'generatedAt': DateTime.now().toIso8601String(),
        'note': 'Конверт не сверён с официальной схемой ИСНА',
      },
      'formCode': _formCode,
      'version': _formVersion,
      'revision': _formRevision,
      'period': {
        'year': data.year,
        'halfYear': data.halfYear,
      },
      'taxpayer': {
        'iin': data.iin,
        'name': data.fullName,
      },
      'declarationType': _declarationTypeField(data),
      'currencyCode': 'KZT',
      'fields': {
        for (final e in _fieldValues(data).entries)
          e.key: double.parse(e.value.toStringAsFixed(2)),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Сохранить/поделиться файлом формы в выбранном формате.
  static Future<void> shareFile(Form910Data data, Form910Format format) async {
    final content = generate(data, format);
    final fileName =
        'form_910_${data.year}_H${data.halfYear}.${format.ext}';
    final bytes = utf8.encode(content);
    await saveAndShareFile(bytes, fileName,
        subject: 'Форма 910.00 — ${data.periodLabel} (${format.label})');
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
