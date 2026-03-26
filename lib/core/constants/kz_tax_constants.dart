/// Константы налогового законодательства Казахстана
/// Источник: Новый НК РК (Закон 214-VIII от 18.07.2025, в силу с 01.01.2026),
///           Закон о бюджете № 239-VIII от 08.12.2025,
///           Закон о ОСМС, Закон о пенсионном обеспечении, Закон о СО
/// Обновлено: март 2026
///
/// Значения загружаются из PostgreSQL (Railway) через /api/config/tax.
/// Хардкод используется как fallback если сервер недоступен.
library kz_tax_constants;

import 'dart:math';

import '../services/tax_config_service.dart';

/// Хелпер для чтения из TaxConfigService с fallback
double _cfg(String key, double fallback) =>
    TaxConfigService.getDouble(key, fallback);

class KzTax {
  KzTax._();

  // ─── МРП (Месячный расчётный показатель) ─────────────────────────────────
  static const double _mrpDefault = 4325.0;
  static double get currentMrp => _cfg('mrp', _mrpDefault);

  // ─── МЗП (Минимальная заработная плата) ──────────────────────────────────
  static const double _mzpDefault = 85000.0;
  static double get currentMzp => _cfg('mzp', _mzpDefault);

  // ═══════════════════════════════════════════════════════════════════════════
  // УПРОЩЁННАЯ ДЕКЛАРАЦИЯ (Форма 910) — Новый НК РК 2026
  // Ставка: 4% от дохода (100% ИПН, СН = 0% для СНР)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Максимальный доход за год (МРП × множитель)
  static double get simplified910YearLimit =>
      currentMrp * _cfg('910_year_mrp', 600000);

  /// Лимит за полугодие (для обратной совместимости)
  static double get simplified910HalfYearLimit => simplified910YearLimit / 2;

  /// Ограничение на кол-во сотрудников
  static int get simplified910MaxEmployees =>
      TaxConfigService.getInt('910_max_employees', 999999);

  /// Ставка 910: 4% (ИПН)
  static double get ipnRate => _cfg('ipn_rate_910', 0.04);

  /// СН для СНР = 0%
  static double get snRate => _cfg('sn_rate_910', 0.0);

  /// Суммарная ставка 910
  static double get simplified910TotalRate => ipnRate + snRate;

  /// Региональные корректировки — маслихат ±50%
  static const double regionalDiscountMin = 0.0;
  static const double regionalDiscountMax = 0.02;

  // ═══════════════════════════════════════════════════════════════════════════
  // ЕЖЕМЕСЯЧНЫЕ СОЦПЛАТЕЖИ "ЗА СЕБЯ" (ИП без сотрудников)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ОПВ: 10% от 1 МЗП
  static double get opvRate => _cfg('opv_rate', 0.10);
  static double get opvMonthly => currentMzp * opvRate;
  static double get opvMaxBase => currentMzp * 50;

  /// ОПВР: 3.5% (2026)
  static double get opvrRate => _cfg('opvr_rate', 0.035);
  static double get opvrMonthly => currentMzp * opvrRate;

  /// СО: 5%
  static double get soRate => _cfg('so_rate', 0.05);
  static double get soMonthly => currentMzp * soRate;
  static double get soMaxBase => currentMzp * 7;

  /// ВОСМС "за себя": 5% от 1.4 МЗП
  static double get vosmsRate => _cfg('vosms_rate_self', 0.05);
  static double get vosmsBaseMultiplier => _cfg('vosms_base_mult', 1.4);
  static double get vosmsMonthly => currentMzp * vosmsBaseMultiplier * vosmsRate;

  /// Итого ежемесячно "за себя" (с ОПВР)
  static double get monthlyTotalSelf =>
      opvMonthly + opvrMonthly + soMonthly + vosmsMonthly;

  /// Итого ежемесячно "за себя" (без ОПВР, для родившихся до 1975)
  static double get monthlyTotalSelfNoOpvr =>
      opvMonthly + soMonthly + vosmsMonthly;

  // ═══════════════════════════════════════════════════════════════════════════
  // СОЦПЛАТЕЖИ ЗА СОТРУДНИКОВ
  // ═══════════════════════════════════════════════════════════════════════════

  /// ОПВ (с сотрудника): 10%
  static double get employeeOpvRate => _cfg('ee_opv_rate', 0.10);

  /// ВОСМС (с сотрудника): 2%, база до 20 МЗП
  static double get employeeVosmsRate => _cfg('ee_vosms_rate', 0.02);
  static double get employeeVosmsMaxBase =>
      currentMzp * _cfg('ee_vosms_max_mult', 20);

  /// ОПВР (работодатель): 3.5% (2026)
  static double get employerOpvrRate => _cfg('emp_opvr_rate', 0.035);

  /// СО (работодатель): 5%
  static double get employerSoRate => _cfg('emp_so_rate', 0.05);

  /// ООСМС (работодатель): 3%, база до 40 МЗП
  static double get employerVosmsRate => _cfg('emp_vosms_rate', 0.03);
  static double get employerVosmsMaxBase =>
      currentMzp * _cfg('emp_vosms_max_mult', 40);

  // ═══════════════════════════════════════════════════════════════════════════
  // ЕСП (Единый совокупный платёж)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Лимит дохода (МРП × множитель)
  static double get espYearLimit =>
      currentMrp * _cfg('esp_year_mrp_limit', 1175);

  /// Платёж: МРП × множитель /мес в городе
  static double get espMonthlyCity =>
      currentMrp * _cfg('esp_mrp_city_mult', 1);

  /// Платёж: МРП × множитель /мес в селе
  static double get espMonthlyRural =>
      currentMrp * _cfg('esp_mrp_rural_mult', 0.5);

  // ═══════════════════════════════════════════════════════════════════════════
  // РЕЖИМ САМОЗАНЯТЫХ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ставка: 4%
  static double get selfEmployedRate => _cfg('self_emp_rate', 0.04);

  /// Лимит дохода (МРП × множитель)
  static double get selfEmployedYearLimit =>
      currentMrp * _cfg('self_emp_year_limit', 3600);

  // ═══════════════════════════════════════════════════════════════════════════
  // НДС — Новый НК РК 2026
  // ═══════════════════════════════════════════════════════════════════════════

  /// Порог НДС (МРП × множитель)
  static double get vatRegistrationThreshold =>
      currentMrp * _cfg('vat_threshold_mrp', 10000);

  /// Ставка НДС: 16%
  static double get vatRate => _cfg('vat_rate', 0.16);

  // ═══════════════════════════════════════════════════════════════════════════
  // ОУР — Прогрессивная шкала ИПН
  // ═══════════════════════════════════════════════════════════════════════════

  /// ИПН базовая ставка: 10%
  static double get generalIpnRate => _cfg('general_ipn_rate', 0.10);

  /// ИПН повышенная ставка: 15%
  static double get generalIpnRateHigh =>
      _cfg('general_ipn_rate_high', 0.15);

  /// Порог для повышенной ставки (МРП × множитель)
  static double get generalIpnThreshold =>
      currentMrp * _cfg('general_ipn_threshold_mrp', 8500);

  /// Базовый вычет ИПН: 30 МРП в месяц
  static double get ipnMonthlyDeduction =>
      currentMrp * _cfg('ipn_deduction_mrp', 30);

  /// Рассчитать ИПН по прогрессивной шкале (годовой доход)
  static double calculateProgressiveIpn(double annualIncome) {
    if (annualIncome <= 0) return 0;
    final threshold = generalIpnThreshold;
    if (annualIncome <= threshold) {
      return annualIncome * generalIpnRate;
    }
    return threshold * generalIpnRate +
        (annualIncome - threshold) * generalIpnRateHigh;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ТОО — ОТЧЁТНОСТЬ В КОМИТЕТ СТАТИСТИКИ (stat.gov.kz)
  // Закон РК «О государственной статистике», Приказ Бюро нацстатистики
  // ═══════════════════════════════════════════════════════════════════════════

  /// Формы статистической отчётности для малого бизнеса (ТОО, ≤100 чел.)
  static const List<StatForm> tooStatForms = [
    StatForm(
      code: '2-МП',
      name: 'Отчёт о деятельности малого предприятия',
      frequency: 'Ежеквартально',
      deadlineDescription: 'До 25 числа месяца после отчётного квартала',
      deadlineMonths: [4, 7, 10, 1],  // апрель, июль, октябрь, январь
      deadlineDay: 25,
      submitTo: 'stat.gov.kz (кабинет респондента)',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // ТОО — НАЛОГОВАЯ ОТЧЁТНОСТЬ (cabinet.salyk.kz)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Основные налоговые формы ТОО (ОУР)
  static const List<TaxForm> tooTaxForms = [
    TaxForm(
      code: '100.00',
      name: 'Декларация по КПН',
      frequency: 'Ежегодно',
      deadlineDescription: 'До 31 марта года, следующего за отчётным',
      deadlineMonths: [3],
      deadlineDay: 31,
    ),
    TaxForm(
      code: '300.00',
      name: 'Декларация по НДС (если плательщик)',
      frequency: 'Ежеквартально',
      deadlineDescription: 'До 15 числа 2-го месяца после отчётного квартала',
      deadlineMonths: [5, 8, 11, 2],
      deadlineDay: 15,
    ),
    TaxForm(
      code: '200.00',
      name: 'Декларация по ИПН и СН (если есть сотрудники)',
      frequency: 'Ежеквартально',
      deadlineDescription: 'До 15 числа 2-го месяца после отчётного квартала',
      deadlineMonths: [5, 8, 11, 2],
      deadlineDay: 15,
    ),
    TaxForm(
      code: '700.00',
      name: 'Земельный налог, имущество, транспорт',
      frequency: 'Ежегодно',
      deadlineDescription: 'До 31 марта года, следующего за отчётным',
      deadlineMonths: [3],
      deadlineDay: 31,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // ДЕДЛАЙНЫ — НК РК и Закон о социальном страховании
  // ═══════════════════════════════════════════════════════════════════════════

  /// Форма 910 — подача и оплата (ст. 688 НК РК)
  static const String deadline910H1Submit = '15 августа';    // за 1-е полугодие
  static const String deadline910H1Pay    = '25 августа';
  static const String deadline910H2Submit = '15 февраля';    // за 2-е полугодие
  static const String deadline910H2Pay    = '25 февраля';

  /// Соцплатежи: до 25 числа следующего месяца
  static const int socialPaymentDeadlineDay = 25;

  // ═══════════════════════════════════════════════════════════════════════════
  // РАСЧЁТЫ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Рассчитать налоги по упрощёнке (910) за полугодие (Новый НК РК 2026)
  /// Ставка 4% — 100% ИПН, СН = 0%. Маслихат может скорректировать ±50%.
  static TaxCalculation910 calculate910(double income, {double regionalDiscount = 0.0}) {
    final effectiveRate = (simplified910TotalRate - regionalDiscount).clamp(0.0, 1.0);
    final ipn = income * effectiveRate;

    return TaxCalculation910(
      income: income,
      ipn: ipn,
      sn: 0, // СН = 0% для СНР с 2026
      totalTax: ipn,
      effectiveIpnRate: effectiveRate,
      effectiveSnRate: 0,
    );
  }

  /// Рассчитать ежемесячные соцплатежи ИП "за себя"
  static SocialPayments calculateMonthlySocial({bool bornBefore1975 = false}) {
    final opv   = opvMonthly;
    final opvr  = bornBefore1975 ? 0.0 : opvrMonthly;
    final so    = soMonthly;
    final vosms = vosmsMonthly;
    return SocialPayments(
      opv:   opv,
      opvr:  opvr,
      so:    so,
      vosms: vosms,
      total: opv + opvr + so + vosms,
    );
  }

  /// Полный расчёт: налоги 910 + соцплатежи за 6 месяцев
  static FullTaxSummary calculateFull910(
    double halfYearIncome, {
    double regionalDiscount = 0.0,
    bool bornBefore1975 = false,
  }) {
    final tax         = calculate910(halfYearIncome, regionalDiscount: regionalDiscount);
    final social      = calculateMonthlySocial(bornBefore1975: bornBefore1975);
    final socialHalfYear = social.total * 6;
    return FullTaxSummary(
      tax:           tax,
      monthlySocial: social,
      socialHalfYear: socialHalfYear,
      grandTotal:    tax.totalTax + socialHalfYear,
    );
  }

  /// Рассчитать налог для самозанятых
  static double calculateSelfEmployed(double income) => income * selfEmployedRate;

  // ═══════════════════════════════════════════════════════════════════════════
  // ТОО (Товарищество с ограниченной ответственностью)
  // ═══════════════════════════════════════════════════════════════════════════

  /// КПН: 20%
  static double get kpnRate => _cfg('kpn_rate', 0.20);

  /// КПН для малого бизнеса на упрощёнке: 0% (до 2028)
  static const double kpnSmallBusinessRate = 0.0;

  /// ИПН у источника (дивиденды): 5%
  static double get dividendTaxRate => _cfg('dividend_tax_rate', 0.05);

  /// Социальный налог ТОО: 6% от ФОТ (Новый НК РК 2026)
  static double get socialTaxTooRate => _cfg('social_tax_too_rate', 0.06);

  /// Расчёт КПН
  static TooTaxCalculation calculateToo({
    required double income,
    required double expenses,
    bool isVatPayer = false,
    int employeeCount = 0,
    double monthlyPayroll = 0,
  }) {
    final taxableIncome = max(0.0, income - expenses);
    final kpn = taxableIncome * kpnRate;

    // НДС
    final vatReceived = isVatPayer ? income * vatRate : 0.0;
    final vatPaid = isVatPayer ? expenses * vatRate : 0.0;
    final vatPayable = max(0.0, vatReceived - vatPaid);

    // Социальный налог за сотрудников: 6% от ФОТ (новый НК РК 2026, без вычета СО)
    final socialTax = max(0.0, monthlyPayroll * socialTaxTooRate) * employeeCount;

    // Dividend tax on remaining profit
    final netProfit = taxableIncome - kpn;
    final dividendTax = netProfit * dividendTaxRate;

    return TooTaxCalculation(
      income: income,
      expenses: expenses,
      taxableIncome: taxableIncome,
      kpn: kpn,
      vatReceived: vatReceived,
      vatPaid: vatPaid,
      vatPayable: vatPayable,
      socialTax: socialTax,
      netProfit: netProfit,
      dividendTax: dividendTax,
      totalTax: kpn + vatPayable + dividendTax,
    );
  }
}

/// Результат расчёта налогов по 910 форме
class TaxCalculation910 {
  final double income;
  final double ipn;
  final double sn;
  final double totalTax;
  final double effectiveIpnRate;
  final double effectiveSnRate;

  const TaxCalculation910({
    required this.income,
    required this.ipn,
    required this.sn,
    required this.totalTax,
    required this.effectiveIpnRate,
    required this.effectiveSnRate,
  });

  double get effectiveRate => income > 0 ? totalTax / income : 0;
}

/// Ежемесячные социальные платежи "за себя"
class SocialPayments {
  final double opv;
  final double opvr;
  final double so;
  final double vosms;
  final double total;

  const SocialPayments({
    required this.opv,
    required this.opvr,
    required this.so,
    required this.vosms,
    required this.total,
  });
}

/// Полная сводка: налоги + соцплатежи
class FullTaxSummary {
  final TaxCalculation910 tax;
  final SocialPayments monthlySocial;
  final double socialHalfYear;
  final double grandTotal;

  const FullTaxSummary({
    required this.tax,
    required this.monthlySocial,
    required this.socialHalfYear,
    required this.grandTotal,
  });

  double get effectiveRate => tax.income > 0 ? grandTotal / tax.income : 0;
}

/// Результат расчёта налогов ТОО
class TooTaxCalculation {
  final double income;
  final double expenses;
  final double taxableIncome;
  final double kpn;
  final double vatReceived;
  final double vatPaid;
  final double vatPayable;
  final double socialTax;
  final double netProfit;
  final double dividendTax;
  final double totalTax;

  const TooTaxCalculation({
    required this.income,
    required this.expenses,
    required this.taxableIncome,
    required this.kpn,
    required this.vatReceived,
    required this.vatPaid,
    required this.vatPayable,
    required this.socialTax,
    required this.netProfit,
    required this.dividendTax,
    required this.totalTax,
  });

  double get effectiveRate => income > 0 ? totalTax / income : 0;
}

/// Форма статистической отчётности
class StatForm {
  final String code;
  final String name;
  final String frequency;
  final String deadlineDescription;
  final List<int> deadlineMonths;
  final int deadlineDay;
  final String submitTo;

  const StatForm({
    required this.code,
    required this.name,
    required this.frequency,
    required this.deadlineDescription,
    required this.deadlineMonths,
    required this.deadlineDay,
    required this.submitTo,
  });
}

/// Форма налоговой отчётности ТОО
class TaxForm {
  final String code;
  final String name;
  final String frequency;
  final String deadlineDescription;
  final List<int> deadlineMonths;
  final int deadlineDay;

  const TaxForm({
    required this.code,
    required this.name,
    required this.frequency,
    required this.deadlineDescription,
    required this.deadlineMonths,
    required this.deadlineDay,
  });
}

/// Налоговые режимы ИП в Казахстане (2026)
enum TaxRegime {
  esp('ЕСП', 'Единый совокупный платёж'),
  selfEmployed('Самозанятый', 'Режим самозанятых (замена патента)'),
  simplified('Упрощёнка', 'Упрощённая декларация (910)'),
  general('ОУР', 'Общеустановленный режим');

  const TaxRegime(this.shortName, this.fullName);
  final String shortName;
  final String fullName;
}
