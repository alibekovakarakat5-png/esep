import 'dart:convert';
import 'package:intl/intl.dart';

import 'file_saver.dart';

import '../models/transaction.dart';
import '../constants/kz_tax_constants.dart';
import '../providers/company_provider.dart';

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

class Form910Service {
  Form910Service._();

  static final _dateFmt = DateFormat('dd.MM.yyyy');

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

  /// Generate XML for form 910.00
  static String generateXml(Form910Data data) {
    final now = DateTime.now();
    final fmt = NumberFormat('0.00');
    final ratePercent = (KzTax.simplified910TotalRate * 100).toStringAsFixed(0);

    return '''<?xml version="1.0" encoding="UTF-8"?>
<declaration>
  <formCode>910.00</formCode>
  <formVersion>2026</formVersion>
  <generatedBy>Esep</generatedBy>
  <generatedAt>${_dateFmt.format(now)}</generatedAt>

  <header>
    <iin>${_escapeXml(data.iin)}</iin>
    <fullName>${_escapeXml(data.fullName)}</fullName>
    <taxPeriod>
      <year>${data.year}</year>
      <halfYear>${data.halfYear}</halfYear>
    </taxPeriod>
    <declarationType>${_escapeXml(data.declarationType)}</declarationType>
    <taxRegime>упрощенная декларация</taxRegime>
  </header>

  <section1 title="Исчисление налогов">
    <field code="910.00.001" name="Доход за налоговый период">${fmt.format(data.income)}</field>
    <field code="910.00.001A" name="Безналичные расчеты">${fmt.format(data.incomeNonCash)}</field>
    <field code="910.00.001B" name="Электронная торговля">${fmt.format(data.incomeEcommerce)}</field>
    <field code="910.00.002" name="Корректировка трансфертного ценообразования">${fmt.format(data.transferPricing)}</field>
    <field code="910.00.003" name="Среднесписочная численность работников">${fmt.format(data.avgEmployees)}</field>
    <field code="910.00.004" name="Среднемесячная з/п на работника">${fmt.format(data.avgMonthlyWage)}</field>
    <field code="910.00.005" name="Исчисленные налоги ($ratePercent%)">${fmt.format(data.calculatedTax)}</field>
    <field code="910.00.006" name="Корректировка налогов">${fmt.format(data.taxAdjustment)}</field>
    <field code="910.00.007" name="Итого налогов">${fmt.format(data.netTax)}</field>
    <field code="910.00.008" name="ИПН">${fmt.format(data.ipn)}</field>
    <field code="910.00.009" name="Социальный налог">${fmt.format(data.socialTax)}</field>
  </section1>

  <section2 title="Исчисление социальных платежей">
    <field code="910.00.010" name="Доход для исчисления СО">${fmt.format(data.soIncome)}</field>
    <field code="910.00.011" name="Сумма СО">${fmt.format(data.soAmount)}</field>
    <field code="910.00.012" name="Доход для исчисления ОПВ">${fmt.format(data.opvIncome)}</field>
    <field code="910.00.013" name="Сумма ОПВ">${fmt.format(data.opvAmount)}</field>
    <field code="910.00.014" name="Сумма ОПВР">${fmt.format(data.opvrAmount)}</field>
    <field code="910.00.015" name="Сумма ВОСМС">${fmt.format(data.vosmsAmount)}</field>
  </section2>

  <totals>
    <totalTax>${fmt.format(data.totalTax)}</totalTax>
    <totalSocial>${fmt.format(data.totalSocial)}</totalSocial>
    <grandTotal>${fmt.format(data.grandTotal)}</grandTotal>
  </totals>
</declaration>''';
  }

  /// Share XML file
  static Future<void> shareXml(Form910Data data) async {
    final xml = generateXml(data);
    final fileName = 'form_910_${data.year}_H${data.halfYear}.xml';
    final bytes = utf8.encode(xml);

    await saveAndShareFile(bytes, fileName, subject: 'Форма 910.00 — ${data.periodLabel}');
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
