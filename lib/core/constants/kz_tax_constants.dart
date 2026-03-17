/// Константы налогового законодательства Казахстана
/// Источник: НК РК 2026, Закон о бюджете № 239-VIII от 08.12.2025,
///           Закон о ОСМС, Закон о пенсионном обеспечении, Закон о СО
/// Обновлено: март 2026
library kz_tax_constants;

import 'dart:math';

class KzTax {
  KzTax._();

  // ─── МРП (Месячный расчётный показатель) ─────────────────────────────────
  // Закон РК «О республиканском бюджете на 2026–2028 годы» № 239-VIII от 08.12.2025
  static const double mrp2025 = 3932.0;
  static const double mrp2026 = 4325.0; // ↑ с 3 932 в 2025
  static double get currentMrp => mrp2026;

  // ─── МЗП (Минимальная заработная плата) ──────────────────────────────────
  static const double mzp2025 = 85000.0;
  static const double mzp2026 = 85000.0; // не изменилась
  static double get currentMzp => mzp2026;

  // ═══════════════════════════════════════════════════════════════════════════
  // УПРОЩЁННАЯ ДЕКЛАРАЦИЯ (Форма 910) — ст. 683 НК РК
  // Ставка: 3% от дохода (1.5% ИПН + 1.5% СН)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Максимальный доход за полугодие: 24 038 МРП (ст. 683 п.2 НК РК)
  static double get simplified910HalfYearLimit => currentMrp * 24038;

  /// Максимальный доход за год
  static double get simplified910YearLimit => simplified910HalfYearLimit * 2;

  /// Макс. кол-во сотрудников (ст. 683 п.2 НК РК)
  static const int simplified910MaxEmployees = 30;

  /// ИПН: 1.5% от дохода (ст. 683 п.1 НК РК)
  static const double ipnRate = 0.015;

  /// СН: 1.5% от дохода (ст. 683 п.1 НК РК)
  static const double snRate = 0.015;

  /// Суммарная ставка 910: 3%
  static const double simplified910TotalRate = ipnRate + snRate;

  /// Региональные корректировки (ст. 686 НК РК)
  static const double regionalDiscountMin = 0.0;
  static const double regionalDiscountMax = 0.02;

  // ═══════════════════════════════════════════════════════════════════════════
  // ЕЖЕМЕСЯЧНЫЕ СОЦПЛАТЕЖИ "ЗА СЕБЯ" (ИП без сотрудников)
  // База расчёта: 1 МЗП (если иное не оговорено)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ОПВ: 10% от 1 МЗП — ст. 25 Закона о пенсионном обеспечении
  static const double opvRate = 0.10;
  static double get opvMonthly => currentMzp * opvRate;
  static double get opvMaxBase => currentMzp * 50;

  /// ОПВР: 3.5% от 1 МЗП (2026) — постепенный рост: 1.5% (2024) → 2.5% (2025) → 3.5% (2026) → 5% (2027)
  /// Не применяется для родившихся до 1975 года
  /// Ст. 26-1 Закона о пенсионном обеспечении
  static const double opvrRate = 0.035;
  static double get opvrMonthly => currentMzp * opvrRate;

  /// СО: 5% от 1 МЗП — ст. 15 Закона о социальном страховании
  static const double soRate = 0.05;
  static double get soMonthly => currentMzp * soRate;
  static double get soMaxBase => currentMzp * 7;

  /// ВОСМС "за себя": 5% от 1.4 МЗП — ст. 28 Закона о ОСМС
  /// (объединяет долю работника 2% + работодателя 3% = 5% от фиксированной базы 1.4 МЗП)
  static const double vosmsRate = 0.05;
  static const double vosmsBaseMultiplier = 1.4;
  static double get vosmsMonthly => currentMzp * vosmsBaseMultiplier * vosmsRate;

  /// Итого ежемесячно "за себя" (с ОПВР)
  static double get monthlyTotalSelf =>
      opvMonthly + opvrMonthly + soMonthly + vosmsMonthly;

  /// Итого ежемесячно "за себя" (без ОПВР, для родившихся до 1975)
  static double get monthlyTotalSelfNoOpvr =>
      opvMonthly + soMonthly + vosmsMonthly;

  // ═══════════════════════════════════════════════════════════════════════════
  // СОЦПЛАТЕЖИ ЗА СОТРУДНИКОВ (работодатель начисляет и удерживает)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ОПВ (с сотрудника): 10%, база 1–50 МЗП
  static const double employeeOpvRate = 0.10;

  /// ВОСМС (с сотрудника): 2%, база до 20 МЗП — ст. 28 Закона о ОСМС
  static const double employeeVosmsRate = 0.02;
  static double get employeeVosmsMaxBase => currentMzp * 20;

  /// ОПВР (работодатель): 3.5% (2026), база 1–50 МЗП
  /// Постепенный рост: 1.5%(2024) → 2.5%(2025) → 3.5%(2026) → 5%(2027)
  static const double employerOpvrRate = 0.035;

  /// СО (работодатель): 5%, база МЗП–7МЗП (от разницы зарплата - ОПВ)
  static const double employerSoRate = 0.05;

  /// ООСМС (работодатель): 3%, база до 40 МЗП — ст. 27 Закона о ОСМС
  static const double employerVosmsRate = 0.03;
  static double get employerVosmsMaxBase => currentMzp * 40;

  // ═══════════════════════════════════════════════════════════════════════════
  // ЕСП (Единый совокупный платёж) — ст. 775-779 НК РК
  // ═══════════════════════════════════════════════════════════════════════════

  /// Лимит дохода: 1 175 МРП в год
  static double get espYearLimit => currentMrp * 1175;

  /// Платёж: 1 МРП/мес в городе
  static double get espMonthlyCity => currentMrp;

  /// Платёж: 0.5 МРП/мес в селе
  static double get espMonthlyRural => currentMrp * 0.5;

  // ═══════════════════════════════════════════════════════════════════════════
  // РЕЖИМ САМОЗАНЯТЫХ (заменил Патент с 2026) — ст. 774-1 НК РК
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ставка: 4% от дохода
  static const double selfEmployedRate = 0.04;

  /// Лимит дохода: 3 528 МРП в год
  static double get selfEmployedYearLimit => currentMrp * 3528;

  // ═══════════════════════════════════════════════════════════════════════════
  // НДС — ст. 367-368 НК РК
  // ═══════════════════════════════════════════════════════════════════════════

  /// Порог обязательной постановки на учёт по НДС: 20 000 МРП за 12 мес
  static double get vatRegistrationThreshold => currentMrp * 20000;

  /// Стандартная ставка НДС: 12%
  static const double vatRate = 0.12;

  // ═══════════════════════════════════════════════════════════════════════════
  // ОУР (Общеустановленный режим) — ст. 317 НК РК
  // ═══════════════════════════════════════════════════════════════════════════

  /// ИПН: 10% от чистого дохода
  static const double generalIpnRate = 0.10;

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

  /// Рассчитать налоги по упрощёнке (910) за полугодие (ст. 683 НК РК)
  static TaxCalculation910 calculate910(double income, {double regionalDiscount = 0.0}) {
    final effectiveIpnRate = (ipnRate - regionalDiscount / 2).clamp(0.0, 1.0);
    final effectiveSnRate  = (snRate  - regionalDiscount / 2).clamp(0.0, 1.0);

    final ipn = income * effectiveIpnRate;
    final sn  = income * effectiveSnRate;

    return TaxCalculation910(
      income: income,
      ipn: ipn,
      sn: sn,
      totalTax: ipn + sn,
      effectiveIpnRate: effectiveIpnRate,
      effectiveSnRate: effectiveSnRate,
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

  /// КПН: 20% от налогооблагаемого дохода (ст. 313 НК РК)
  static const double kpnRate = 0.20;

  /// КПН для малого бизнеса на упрощёнке: 0% (ст. 697 НК РК, до 2028)
  static const double kpnSmallBusinessRate = 0.0;

  /// ИПН у источника (дивиденды): 5% (ст. 320 НК РК)
  static const double dividendTaxRate = 0.05;

  /// Социальный налог ТОО: 9.5% от (ФОТ - ОПВ работников) (ст. 485 НК РК)
  static const double socialTaxTooRate = 0.095;

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

    // Социальный налог за сотрудников (9.5% от ФОТ - ОПВ)
    final opvEmployees = monthlyPayroll * employeeOpvRate;
    final socialTax = max(0.0, (monthlyPayroll - opvEmployees) * socialTaxTooRate) * employeeCount;

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
