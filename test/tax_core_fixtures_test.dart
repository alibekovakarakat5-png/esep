// Тест на расхождение Dart ↔ Node (волна 5 спеки
// docs/superpowers/specs/2026-08-06-tax-core-node-design.md).
//
// Гоняет ЕДИНЫЙ набор фикстур server/src/services/tax/__fixtures__/ против
// KzTax и Form910Service. Те же фикстуры проверяют Node-модуль services/tax
// (server/test/tax_calc.test.js и tax_form910.test.js). Разъехались формулы
// в одном из мест — этот тест падает в CI, сборка не выходит.
//
// Локально dart.exe заблокирован Device Guard — тест выполняется в GitHub
// Actions (build-release.yml, job tests).
//
// Кейсы с ratesOverride пропускаются: у TaxConfigService нет тестовой
// инъекции ставок, KzTax считает по fallback-константам. Совпадение
// fallback'ов с каноном rates_2026.json стережёт блок «канон ставок» ниже
// (и server/test/tax_rates.test.js с Node-стороны). Кастомные ставки
// покрыты Node-тестами.
//
// Запуск: flutter test test/tax_core_fixtures_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:esep/core/constants/kz_tax_constants.dart';
import 'package:esep/core/models/transaction.dart';
import 'package:esep/core/providers/company_provider.dart';
import 'package:esep/core/services/form910_service.dart';

const _fixturesDir = 'server/src/services/tax/__fixtures__';

Map<String, dynamic> _readJson(String name) =>
    jsonDecode(File('$_fixturesDir/$name').readAsStringSync())
        as Map<String, dynamic>;

double _num(dynamic v, [double fallback = 0]) =>
    v == null ? fallback : (v as num).toDouble();

/// Рекурсивное сравнение с фикстурой: числа — с относительной толерантностью
/// 1e-9 (как в server/test/_helpers.js), остальное — строгое равенство.
void expectClose(dynamic actual, dynamic expected, String path) {
  if (expected is num) {
    expect(actual, isA<num>(), reason: '$path: ожидалось число');
    final a = (actual as num).toDouble();
    final e = expected.toDouble();
    var scale = a.abs() > e.abs() ? a.abs() : e.abs();
    if (scale < 1) scale = 1;
    expect(a, closeTo(e, scale * 1e-9), reason: path);
  } else if (expected is Map) {
    expect(actual, isA<Map>(), reason: '$path: ожидался объект');
    for (final k in expected.keys) {
      expectClose((actual as Map)[k], expected[k], '$path.$k');
    }
  } else {
    expect(actual, equals(expected), reason: path);
  }
}

Map<String, dynamic> _tax910ToMap(TaxCalculation910 r) => {
      'income': r.income,
      'ipn': r.ipn,
      'sn': r.sn,
      'totalTax': r.totalTax,
      'effectiveIpnRate': r.effectiveIpnRate,
      'effectiveSnRate': r.effectiveSnRate,
      'effectiveRate': r.effectiveRate,
    };

Map<String, dynamic> _socialToMap(SocialPayments s) => {
      'opv': s.opv,
      'opvr': s.opvr,
      'so': s.so,
      'vosms': s.vosms,
      'total': s.total,
    };

Map<String, dynamic> _form910ToMap(Form910Data d) => {
      'iin': d.iin,
      'fullName': d.fullName,
      'halfYear': d.halfYear,
      'year': d.year,
      'declarationType': d.declarationType,
      'income': d.income,
      'incomeNonCash': d.incomeNonCash,
      'incomeEcommerce': d.incomeEcommerce,
      'transferPricing': d.transferPricing,
      'avgEmployees': d.avgEmployees,
      'avgMonthlyWage': d.avgMonthlyWage,
      'calculatedTax': d.calculatedTax,
      'taxAdjustment': d.taxAdjustment,
      'netTax': d.netTax,
      'ipn': d.ipn,
      'socialTax': d.socialTax,
      'soIncome': d.soIncome,
      'soAmount': d.soAmount,
      'opvIncome': d.opvIncome,
      'opvAmount': d.opvAmount,
      'opvrAmount': d.opvrAmount,
      'vosmsAmount': d.vosmsAmount,
      'totalTax': d.totalTax,
      'totalSocial': d.totalSocial,
      'grandTotal': d.grandTotal,
      'periodLabel': d.periodLabel,
    };

Form910Data _calcForm910(Map<String, dynamic> input) {
  final rawTx = (input['transactions'] as List? ?? const []);
  final txs = <Transaction>[];
  for (var i = 0; i < rawTx.length; i++) {
    final t = rawTx[i] as Map<String, dynamic>;
    txs.add(Transaction(
      id: 'fx-$i',
      title: 'fixture',
      amount: _num(t['amount']),
      isIncome: t['isIncome'] as bool? ?? false,
      date: DateTime.parse(t['date'] as String),
      source: t['source'] as String?,
    ));
  }
  return Form910Service.calculate(
    transactions: txs,
    company: CompanyInfo(
      name: input['fullName'] as String,
      iin: input['iin'] as String,
    ),
    halfYear: input['halfYear'] as int,
    year: input['year'] as int,
    employeeCount: input['employeeCount'] as int? ?? 0,
    totalPayroll: _num(input['totalPayroll']),
    bornBefore1975: input['bornBefore1975'] as bool? ?? false,
  );
}

/// Form910Data с нулями — для проверки маппинга типа декларации.
Form910Data _emptyForm(String declarationType) => Form910Data(
      iin: '850101300123',
      fullName: 'ИП Тест',
      halfYear: 1,
      year: 2026,
      declarationType: declarationType,
      income: 0,
      calculatedTax: 0,
      netTax: 0,
      ipn: 0,
      socialTax: 0,
      soIncome: 0,
      soAmount: 0,
      opvIncome: 0,
      opvAmount: 0,
      opvrAmount: 0,
      vosmsAmount: 0,
    );

void main() {
  final canon = _readJson('rates_2026.json');
  final canonRates = canon['rates'] as Map<String, dynamic>;
  final calcFixtures = _readJson('calc_cases.json');
  final formFixtures = _readJson('form910_cases.json');

  // ── Канон ставок: fallback-константы Dart == rates_2026.json ─────────────
  group('канон ставок', () {
    test('fallback-и KzTax совпадают с rates_2026.json', () {
      expectClose(KzTax.currentMrp, canonRates['mrp'], 'mrp');
      expectClose(KzTax.currentMzp, canonRates['mzp'], 'mzp');
      expectClose(KzTax.ipnRate, canonRates['ipn_rate_910'], 'ipn_rate_910');
      expectClose(KzTax.snRate, canonRates['sn_rate_910'], 'sn_rate_910');
      expectClose(KzTax.opvRate, canonRates['opv_rate'], 'opv_rate');
      expectClose(KzTax.opvrRate, canonRates['opvr_rate'], 'opvr_rate');
      expectClose(KzTax.soRate, canonRates['so_rate'], 'so_rate');
      expectClose(KzTax.vosmsRate, canonRates['vosms_rate_self'], 'vosms_rate_self');
      expectClose(
          KzTax.vosmsBaseMultiplier, canonRates['vosms_base_mult'], 'vosms_base_mult');
      expectClose(KzTax.selfEmployedRate, canonRates['self_emp_rate'], 'self_emp_rate');
      expectClose(KzTax.vatRate, canonRates['vat_rate'], 'vat_rate');
      expectClose(KzTax.generalIpnRate, canonRates['general_ipn_rate'], 'general_ipn_rate');
      expectClose(KzTax.generalIpnRateHigh, canonRates['general_ipn_rate_high'],
          'general_ipn_rate_high');
      expectClose(KzTax.kpnRate, canonRates['kpn_rate'], 'kpn_rate');
      expectClose(
          KzTax.socialTaxTooRate, canonRates['social_tax_too_rate'], 'social_tax_too_rate');
      expectClose(
          KzTax.dividendTaxRate, canonRates['dividend_tax_rate'], 'dividend_tax_rate');
    });
  });

  // ── Расчёты: единые фикстуры calc_cases.json ─────────────────────────────
  group('паритет Dart ↔ Node (calc)', () {
    for (final raw in (calcFixtures['cases'] as List)) {
      final c = raw as Map<String, dynamic>;
      if (c.containsKey('ratesOverride')) {
        // Нет инъекции ставок в TaxConfigService — кастомные ставки
        // покрыты Node-тестами (см. шапку файла).
        continue;
      }
      test('calc: ${c['id']}', () {
        final o = (c['options'] as Map<String, dynamic>?) ?? const {};
        final fn = c['fn'] as String;
        final dynamic actual;
        switch (fn) {
          case 'calculate910':
            actual = _tax910ToMap(KzTax.calculate910(
              _num(c['income']),
              regionalAdjustment: _num(o['regionalAdjustment']),
              regionalDiscount: _num(o['regionalDiscount']),
            ));
          case 'calculateMonthlySocial':
            actual = _socialToMap(KzTax.calculateMonthlySocial(
              bornBefore1975: o['bornBefore1975'] as bool? ?? false,
            ));
          case 'calculateFull910':
            {
              final r = KzTax.calculateFull910(
                _num(c['income']),
                regionalAdjustment: _num(o['regionalAdjustment']),
                regionalDiscount: _num(o['regionalDiscount']),
                bornBefore1975: o['bornBefore1975'] as bool? ?? false,
              );
              actual = {
                'tax': _tax910ToMap(r.tax),
                'monthlySocial': _socialToMap(r.monthlySocial),
                'socialHalfYear': r.socialHalfYear,
                'grandTotal': r.grandTotal,
                'effectiveRate': r.effectiveRate,
              };
            }
          case 'calculateProgressiveIpn':
            actual = KzTax.calculateProgressiveIpn(_num(c['income']));
          case 'calculateSelfEmployed':
            actual = KzTax.calculateSelfEmployed(_num(c['income']));
          case 'calculateTooTax':
            {
              final input = c['input'] as Map<String, dynamic>;
              final r = KzTax.calculateToo(
                income: _num(input['income']),
                expenses: _num(input['expenses']),
                isVatPayer: input['isVatPayer'] as bool? ?? false,
                employeeCount: input['employeeCount'] as int? ?? 0,
                monthlyPayroll: _num(input['monthlyPayroll']),
                kpnRateOverride: input.containsKey('kpnRateOverride')
                    ? _num(input['kpnRateOverride'])
                    : null,
              );
              actual = {
                'income': r.income,
                'expenses': r.expenses,
                'taxableIncome': r.taxableIncome,
                'kpn': r.kpn,
                'vatReceived': r.vatReceived,
                'vatPaid': r.vatPaid,
                'vatPayable': r.vatPayable,
                'socialTax': r.socialTax,
                'netProfit': r.netProfit,
                'dividendTax': r.dividendTax,
                'totalTax': r.totalTax,
                'effectiveRate': r.effectiveRate,
              };
            }
          case 'selfEmployedLimit':
            // Месячного лимита в KzTax нет (он платформенный) — множитель
            // берём из канона, mrp — из Dart: связывает mrp обеих сторон.
            actual = {
              'monthlyTenge':
                  KzTax.currentMrp * _num(canonRates['self_emp_month_limit']),
              'yearlyTenge': KzTax.selfEmployedYearLimit,
            };
          case 'vatThreshold':
            actual = {
              'thresholdTenge': KzTax.vatRegistrationThreshold,
              'rate': KzTax.vatRate,
            };
          case 'simplified910YearLimit':
            actual = KzTax.simplified910YearLimit;
          case 'simplified910HalfYearLimit':
            actual = KzTax.simplified910HalfYearLimit;
          case 'ipMonthlySocialTax':
            actual =
                KzTax.ipMonthlySocialTax(employees: o['employees'] as int? ?? 0);
          default:
            fail('Нет диспетчера для fn=$fn (кейс ${c['id']})');
        }
        expectClose(actual, c['expected'], c['id'] as String);
      });
    }
  });

  // ── Форма 910: единые фикстуры form910_cases.json ────────────────────────
  group('паритет Dart ↔ Node (форма 910)', () {
    for (final raw in (formFixtures['cases'] as List)) {
      final c = raw as Map<String, dynamic>;
      test('form910: ${c['id']}', () {
        final data = _calcForm910(c['input'] as Map<String, dynamic>);
        expectClose(_form910ToMap(data), c['expected'], c['id'] as String);
      });
    }

    test('form910: XML совпадает с эталоном (СОНО-конверт)', () {
      final xc = formFixtures['xmlCase'] as Map<String, dynamic>;
      final caseFx = (formFixtures['cases'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((x) => x['id'] == xc['caseId']);
      final data = _calcForm910(caseFx['input'] as Map<String, dynamic>);
      // Дата генерации в Dart не инъектируется (DateTime.now()) — подставляем
      // сегодняшнюю в эталон, как договорено в фикстуре ({{GEN_DATE}}).
      final expected = File('$_fixturesDir/${xc['expectedXmlFile']}')
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceAll(
              '{{GEN_DATE}}', DateFormat('dd.MM.yyyy').format(DateTime.now()))
          .trimRight();
      final actual =
          Form910Service.generateXml(data).replaceAll('\r\n', '\n').trimRight();
      expect(actual, equals(expected));
    });

    test('form910: JSON (ИСНА) — конверт и значения полей', () {
      final caseFx = (formFixtures['cases'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((x) => x['id'] == 'h1-main');
      final data = _calcForm910(caseFx['input'] as Map<String, dynamic>);
      final doc = jsonDecode(Form910Service.generateJson(data))
          as Map<String, dynamic>;
      expect(doc['formCode'], '910.00');
      expect(doc['declarationType'], 'dt_main');
      expect(doc['currencyCode'], 'KZT');
      expectClose(doc['period'], {'year': 2026, 'halfYear': 1}, 'period');
      expectClose(
          doc['fields'], caseFx['expectedFields'], 'fields');
    });

    for (final raw in (formFixtures['declarationTypes'] as List)) {
      final dt = raw as Map<String, dynamic>;
      test('form910: тип декларации «${dt['type']}» → <${dt['field']}>', () {
        final data = _emptyForm(dt['type'] as String);
        final xml = Form910Service.generateXml(data);
        expect(xml, contains('<${dt['field']}>1</${dt['field']}>'));
        final doc = jsonDecode(Form910Service.generateJson(data))
            as Map<String, dynamic>;
        expect(doc['declarationType'], dt['field']);
      });
    }

    test('form910: XML-экранирование спецсимволов в имени', () {
      final esc = formFixtures['xmlEscaping'] as Map<String, dynamic>;
      final caseFx = (formFixtures['cases'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((x) => x['id'] == 'h1-main');
      final input =
          Map<String, dynamic>.from(caseFx['input'] as Map<String, dynamic>);
      input['fullName'] = esc['fullName'];
      final xml = Form910Service.generateXml(_calcForm910(input));
      expect(xml, contains(esc['expectedInXml'] as String));
    });
  });
}
