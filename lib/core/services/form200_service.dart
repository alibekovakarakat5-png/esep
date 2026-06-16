import 'dart:convert';
import 'dart:math';

import '../constants/kz_tax_constants.dart';
import '../models/employee.dart';
import 'file_saver.dart';

/// ─── Форма 200.00 — Декларация по ИПН и социальному налогу ──────────────────
///
/// Версия 33, ревизия 142 (схема КГД form_200_00_v33_r142).
/// Период действия схемы: 2023-2026.
///
/// Форма квартальная. Для каждого из 3 месяцев квартала и по каждому
/// работнику считаются: ИПН, ОПВ, СН, СО, ВОСМС (взносы), ООСМС (отчисления).
///
/// ВАЖНО: расчёт ИПН/ОПВ/СО/ВОСМС/ООСМС — однозначный (ставки НК РК 2026).
/// Расчёт СН (социального налога) в реформе 2026 уточняется — помечен как
/// требующий проверки бухгалтером. Маппинг строк взят из официальной схемы:
///   200.00.001 = ИПН с доходов работников
///   200.00.002 = ОПВ (обязательные пенсионные взносы)
///   200.00.005 = СН (социальный налог)
///   200.00.008 = СО (социальные отчисления)
///   200.00.010 = ООСМС (отчисления на ОСМС, работодатель)
///   200.00.011 = ВОСМС (взносы на ОСМС, работник)

enum Form200Format { xmlSono, jsonIsna }

extension Form200FormatExt on Form200Format {
  String get ext => this == Form200Format.xmlSono ? 'xml' : 'json';
  String get label =>
      this == Form200Format.xmlSono ? 'XML — СОНО' : 'JSON — КНП ИСНА';
}

/// Тип налогоплательщика — влияет на расчёт СН.
enum TaxpayerKind { ip, too }

/// Расчёт по одной строке за квартал (3 месяца + итог).
class Form200Line {
  final String code; // например '200.00.001'
  final String title;
  final double m1;
  final double m2;
  final double m3;

  const Form200Line({
    required this.code,
    required this.title,
    required this.m1,
    required this.m2,
    required this.m3,
  });

  double get total => m1 + m2 + m3;
}

class Form200Data {
  final String iin;
  final String fullName;
  final int year;
  final int quarter; // 1..4
  final TaxpayerKind kind;
  final int employeeCount;
  final String declarationType; // main / regular / additional / final

  final Form200Line ipn; // 001
  final Form200Line opv; // 002
  final Form200Line sn; // 005
  final Form200Line so; // 008
  final Form200Line oosms; // 010
  final Form200Line vosms; // 011

  const Form200Data({
    required this.iin,
    required this.fullName,
    required this.year,
    required this.quarter,
    required this.kind,
    required this.employeeCount,
    required this.declarationType,
    required this.ipn,
    required this.opv,
    required this.sn,
    required this.so,
    required this.oosms,
    required this.vosms,
  });

  List<Form200Line> get allLines => [ipn, opv, sn, so, oosms, vosms];

  /// Общая сумма к перечислению за квартал (все обязательства).
  double get grandTotal =>
      ipn.total + opv.total + sn.total + so.total + oosms.total + vosms.total;

  String get periodLabel => '$quarter квартал $year';

  /// Месяцы квартала (номера 1-12)
  List<int> get monthNumbers {
    final start = (quarter - 1) * 3 + 1;
    return [start, start + 1, start + 2];
  }
}

class Form200Service {
  static const _formCode = '200.00';
  static const _formVersion = '33';
  static const _formRevision = '142';

  // ─── Расчёт по одному работнику за один месяц ──────────────────────────────
  static _MonthlyPerEmployee _calcEmployeeMonth(Employee e) {
    final g = e.monthlySalary;
    if (g <= 0) {
      return const _MonthlyPerEmployee(
          ipn: 0, opv: 0, sn: 0, so: 0, oosms: 0, vosms: 0);
    }

    // ОПВ работника: 10%, база до 50 МЗП
    final opvBase = min(g, KzTax.currentMzp * 50);
    final opv = opvBase * KzTax.employeeOpvRate;

    // ВОСМС работника (взносы): 2%, база до 20 МЗП
    final vosmsBase = min(g, KzTax.currentMzp * 20);
    final vosms = vosmsBase * KzTax.employeeVosmsRate;

    // ИПН: (ЗП − ОПВ − 30 МРП) × 10%. База как в зарплатном калькуляторе.
    final ipnTaxable = max(0.0, g - opv - KzTax.ipnMonthlyDeduction);
    final ipn = ipnTaxable * KzTax.generalIpnRate;

    // СО (соц. отчисления, работодатель): 5%, база [1 МЗП; 7 МЗП]
    final soBase =
        max(KzTax.currentMzp, min(g - opv, KzTax.currentMzp * 7));
    final so = soBase * KzTax.employerSoRate;

    // ООСМС (отчисления работодателя): 3%, база до 40 МЗП
    final oosmsBase = min(g, KzTax.currentMzp * 40);
    final oosms = oosmsBase * KzTax.employerVosmsRate;

    // СН (социальный налог), НК-2026: 6% от (доход − ОПВ − ВОСМС), БЕЗ взаимозачёта СО.
    // Взаимозачёт СО отменён с 2026. Мин. база — 14 МРП, если объект меньше.
    final snObject = max(0.0, g - opv - vosms);
    final minSnBase = KzTax.currentMrp * 14;
    final snBase = snObject < minSnBase ? minSnBase : snObject;
    final sn = snBase * KzTax.employeeSocialTaxRate;

    return _MonthlyPerEmployee(
      ipn: ipn,
      opv: opv,
      sn: sn,
      so: so,
      oosms: oosms,
      vosms: vosms,
    );
  }

  /// Главный расчёт формы 200 за квартал.
  ///
  /// [monthlyEmployees] — по индексу 0/1/2 список работников в каждом месяце
  /// квартала. Если у тебя одинаковый штат все 3 месяца — передай один и тот же
  /// список трижды (см. helper [calculateUniform]).
  static Form200Data calculate({
    required String iin,
    required String fullName,
    required int year,
    required int quarter,
    required TaxpayerKind kind,
    required List<List<Employee>> monthlyEmployees, // length 3
    String declarationType = 'main',
  }) {
    assert(monthlyEmployees.length == 3, 'Нужны данные за 3 месяца квартала');

    final agg = List.generate(3, (_) => _MonthlyAgg());
    int maxHeadcount = 0;

    for (var m = 0; m < 3; m++) {
      final list = monthlyEmployees[m];
      maxHeadcount = max(maxHeadcount, list.length);
      for (final e in list) {
        final r = _calcEmployeeMonth(e);
        agg[m].ipn += r.ipn;
        agg[m].opv += r.opv;
        agg[m].sn += r.sn;
        agg[m].so += r.so;
        agg[m].oosms += r.oosms;
        agg[m].vosms += r.vosms;
      }
    }

    // Для ИП на ОУР: социальный налог — фиксированная сумма в МРП,
    // а не процент с ФОТ. Перекрываем расчёт СН.
    if (kind == TaxpayerKind.ip) {
      for (var m = 0; m < 3; m++) {
        final emp = monthlyEmployees[m].length;
        agg[m].sn = KzTax.ipMonthlySocialTax(employees: emp);
      }
    }

    Form200Line line(String code, String title, double Function(_MonthlyAgg) sel) =>
        Form200Line(
          code: code,
          title: title,
          m1: _round(sel(agg[0])),
          m2: _round(sel(agg[1])),
          m3: _round(sel(agg[2])),
        );

    return Form200Data(
      iin: iin,
      fullName: fullName,
      year: year,
      quarter: quarter,
      kind: kind,
      employeeCount: maxHeadcount,
      declarationType: declarationType,
      ipn: line('200.00.001', 'ИПН с доходов работников', (a) => a.ipn),
      opv: line('200.00.002', 'ОПВ (обязательные пенсионные взносы)', (a) => a.opv),
      sn: line('200.00.005', 'Социальный налог (СН)', (a) => a.sn),
      so: line('200.00.008', 'Социальные отчисления (СО)', (a) => a.so),
      oosms: line('200.00.010', 'ООСМС (отчисления работодателя)', (a) => a.oosms),
      vosms: line('200.00.011', 'ВОСМС (взносы работника)', (a) => a.vosms),
    );
  }

  /// Упрощённый расчёт: одинаковый штат все 3 месяца квартала.
  static Form200Data calculateUniform({
    required String iin,
    required String fullName,
    required int year,
    required int quarter,
    required TaxpayerKind kind,
    required List<Employee> employees,
    String declarationType = 'main',
  }) {
    return calculate(
      iin: iin,
      fullName: fullName,
      year: year,
      quarter: quarter,
      kind: kind,
      monthlyEmployees: [employees, employees, employees],
      declarationType: declarationType,
    );
  }

  static double _round(double v) => (v * 100).round() / 100;

  // ─── Маппинг строк → официальные поля схемы ────────────────────────────────
  // Поля: field_200_00_NNN_M, где M = 1/2/3 (месяцы), _4 = итог за квартал.
  static Map<String, double> _fieldValues(Form200Data d) {
    final map = <String, double>{};
    void put(String line, Form200Line v) {
      map['field_200_00_${line}_1'] = v.m1;
      map['field_200_00_${line}_2'] = v.m2;
      map['field_200_00_${line}_3'] = v.m3;
      map['field_200_00_${line}_4'] = v.total;
    }

    put('001', d.ipn);
    put('002', d.opv);
    put('005', d.sn);
    put('008', d.so);
    put('010', d.oosms);
    put('011', d.vosms);
    return map;
  }

  static String _declarationTypeField(Form200Data d) {
    switch (d.declarationType) {
      case 'regular':
        return 'dt_regular';
      case 'additional':
        return 'dt_additional';
      case 'final':
        return 'dt_final';
      case 'notice':
        return 'dt_notice';
      default:
        return 'dt_main';
    }
  }

  static String generate(Form200Data data, Form200Format format) =>
      format == Form200Format.xmlSono
          ? generateXml(data)
          : generateJson(data);

  /// XML для СОНО. Имена полей — официальные из схемы v33 r142.
  /// ⚠ Корневой конверт реализован по образцу 910 — сверить с реальным
  /// экспортом из 1С/СОНО перед подачей.
  static String generateXml(Form200Data data) {
    final fields = _fieldValues(data);
    final dtField = _declarationTypeField(data);
    final fieldXml = fields.entries
        .map((e) => '  <${e.key}>${e.value.toStringAsFixed(2)}</${e.key}>')
        .join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!--
  Форма 200.00 (версия $_formVersion, ревизия $_formRevision) — сгенерирована Esep.
  Имена полей — из официального пакета КГД form_200_00_v33_r142.
  Корневой конверт по образцу 910: ПЕРЕД ПОДАЧЕЙ сверить с экспортом из 1С/СОНО.
  СН (строка 005) — расчёт по НК 2026, уточнить у бухгалтера.
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

  /// JSON для КНП ИСНА. ⚠ Схема конверта ИСНА публично не опубликована.
  static String generateJson(Form200Data data) {
    final payload = {
      '_meta': {
        'generatedBy': 'Esep',
        'generatedAt': DateTime.now().toIso8601String(),
        'note': 'Конверт не сверён с официальной схемой ИСНА. '
            'СН (200.00.005) — расчёт НК 2026, проверить у бухгалтера.',
      },
      'formCode': _formCode,
      'version': _formVersion,
      'revision': _formRevision,
      'period': {'year': data.year, 'quarter': data.quarter},
      'taxpayer': {
        'iin': data.iin,
        'name': data.fullName,
        'kind': data.kind == TaxpayerKind.ip ? 'ip' : 'too',
      },
      'declarationType': _declarationTypeField(data),
      'currencyCode': 'KZT',
      'lines': {
        for (final l in data.allLines)
          l.code: {
            'title': l.title,
            'm1': _round(l.m1),
            'm2': _round(l.m2),
            'm3': _round(l.m3),
            'total': _round(l.total),
          },
      },
      'fields': {
        for (final e in _fieldValues(data).entries)
          e.key: double.parse(e.value.toStringAsFixed(2)),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Сохранить/поделиться файлом формы.
  static Future<void> shareFile(Form200Data data, Form200Format format) async {
    final content = generate(data, format);
    final fileName = 'form_200_${data.year}_Q${data.quarter}.${format.ext}';
    final bytes = utf8.encode(content);
    await saveAndShareFile(bytes, fileName,
        subject: 'Форма 200.00 — ${data.periodLabel} (${format.label})');
  }

  static String _escapeXml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class _MonthlyPerEmployee {
  final double ipn, opv, sn, so, oosms, vosms;
  const _MonthlyPerEmployee({
    required this.ipn,
    required this.opv,
    required this.sn,
    required this.so,
    required this.oosms,
    required this.vosms,
  });
}

class _MonthlyAgg {
  double ipn = 0, opv = 0, sn = 0, so = 0, oosms = 0, vosms = 0;
}
