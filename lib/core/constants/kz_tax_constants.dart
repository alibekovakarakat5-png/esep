/// Константы налогового законодательства Казахстана
/// Обновлено под Налоговый кодекс 2026 года
library kz_tax_constants;

class KzTax {
  KzTax._();

  // ─── МРП (Месячный расчётный показатель) ─────────────────────────────────
  static const double mrp2025 = 3932.0;
  static const double mrp2026 = 4205.0;
  static double get currentMrp => mrp2026;

  // ─── МЗП (Минимальная заработная плата) ──────────────────────────────────
  static const double mzp2025 = 85000.0;
  static const double mzp2026 = 85000.0; // не изменилась
  static double get currentMzp => mzp2026;

  // ═══════════════════════════════════════════════════════════════════════════
  // УПРОЩЁННАЯ ДЕКЛАРАЦИЯ (Форма 910) — с 2026: ставка 4%
  // ═══════════════════════════════════════════════════════════════════════════

  /// Максимальный доход за полугодие (24 038 МРП)
  static double get simplified910HalfYearLimit => currentMrp * 24038;

  /// Максимальный доход за год
  static double get simplified910YearLimit => simplified910HalfYearLimit * 2;

  /// Макс. кол-во сотрудников
  static const int simplified910MaxEmployees = 30;

  /// ИПН: 2% от дохода (было 1.5%, стало 2% с 2026)
  static const double ipnRate = 0.02;

  /// СН: 2% от дохода (было 1.5%, стало 2% с 2026)
  static const double snRate = 0.02;

  /// Суммарная ставка 910: 4% (было 3%)
  static const double simplified910TotalRate = ipnRate + snRate;

  /// Региональные корректировки (±50% в зависимости от региона)
  /// Многие регионы дают скидку 2-3%
  static const double regionalDiscountMin = 0.0;
  static const double regionalDiscountMax = 0.02;

  // ═══════════════════════════════════════════════════════════════════════════
  // ЕЖЕМЕСЯЧНЫЕ СОЦПЛАТЕЖИ "ЗА СЕБЯ" (ИП без сотрудников)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ОПВ: 10% от 1 МЗП — обязательные пенсионные взносы
  static const double opvRate = 0.10;
  static double get opvMonthly => currentMzp * opvRate;
  static double get opvMaxBase => currentMzp * 50; // макс. база для сотрудников

  /// ОПВР: 3.5% от 1 МЗП — обязательные пенсионные взносы работодателя
  /// Не применяется для родившихся до 1975 года
  static const double opvrRate = 0.035;
  static double get opvrMonthly => currentMzp * opvrRate;

  /// СО: 5% от 1 МЗП — социальные отчисления (было 3.5%, стало 5% с 2026)
  static const double soRate = 0.05;
  static double get soMonthly => currentMzp * soRate;
  static double get soMaxBase => currentMzp * 7;

  /// ВОСМС: 5% от 1.4 МЗП — взносы на обязательное медстрахование
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
  // ЕСП (Единый совокупный платёж)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Лимит дохода: 1 175 МРП в год
  static double get espYearLimit => currentMrp * 1175;

  /// Платёж: 1 МРП/мес в городе
  static double get espMonthlyCity => currentMrp;

  /// Платёж: 0.5 МРП/мес в селе
  static double get espMonthlyRural => currentMrp * 0.5;

  // ═══════════════════════════════════════════════════════════════════════════
  // САМОЗАНЯТЫЕ (заменил Патент с 2026 года)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ставка: 4% от дохода (замена патента 1%)
  static const double selfEmployedRate = 0.04;

  /// Лимит дохода: 3 528 МРП в год
  static double get selfEmployedYearLimit => currentMrp * 3528;

  // ═══════════════════════════════════════════════════════════════════════════
  // НДС
  // ═══════════════════════════════════════════════════════════════════════════

  /// Порог обязательной регистрации по НДС: 20 000 МРП за 12 мес
  static double get vatRegistrationThreshold => currentMrp * 20000;

  /// Стандартная ставка НДС
  static const double vatRate = 0.12;

  // ═══════════════════════════════════════════════════════════════════════════
  // ОУР (Общеустановленный режим)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ИПН для ОУР: 10% от чистого дохода
  static const double generalIpnRate = 0.10;

  // ═══════════════════════════════════════════════════════════════════════════
  // ДЕДЛАЙНЫ (Форма 910)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Сроки подачи и оплаты
  static const String deadline910H1Submit = '15 августа';
  static const String deadline910H1Pay = '25 августа';
  static const String deadline910H2Submit = '15 февраля';
  static const String deadline910H2Pay = '25 февраля';

  /// Ежемесячные соцплатежи: до 25 числа следующего месяца
  static const int socialPaymentDeadlineDay = 25;

  // ═══════════════════════════════════════════════════════════════════════════
  // РАСЧЁТЫ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Рассчитать налоги по упрощёнке (910) за полугодие
  static TaxCalculation910 calculate910(double income, {double regionalDiscount = 0.0}) {
    final effectiveIpnRate = (ipnRate - regionalDiscount / 2).clamp(0.0, 1.0);
    final effectiveSnRate = (snRate - regionalDiscount / 2).clamp(0.0, 1.0);

    final ipn = income * effectiveIpnRate;
    final sn = income * effectiveSnRate;

    return TaxCalculation910(
      income: income,
      ipn: ipn,
      sn: sn,
      totalTax: ipn + sn,
      effectiveIpnRate: effectiveIpnRate,
      effectiveSnRate: effectiveSnRate,
    );
  }

  /// Рассчитать ежемесячные соцплатежи "за себя"
  static SocialPayments calculateMonthlySocial({bool bornBefore1975 = false}) {
    final opv = opvMonthly;
    final opvr = bornBefore1975 ? 0.0 : opvrMonthly;
    final so = soMonthly;
    final vosms = vosmsMonthly;
    return SocialPayments(
      opv: opv,
      opvr: opvr,
      so: so,
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
    final tax = calculate910(halfYearIncome, regionalDiscount: regionalDiscount);
    final social = calculateMonthlySocial(bornBefore1975: bornBefore1975);
    final socialHalfYear = social.total * 6;
    return FullTaxSummary(
      tax: tax,
      monthlySocial: social,
      socialHalfYear: socialHalfYear,
      grandTotal: tax.totalTax + socialHalfYear,
    );
  }

  /// Рассчитать налог для самозанятых (замена патента)
  static double calculateSelfEmployed(double income) => income * selfEmployedRate;
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

/// Налоговые режимы ИП в Казахстане (обновлено 2026)
enum TaxRegime {
  esp('ЕСП', 'Единый совокупный платёж'),
  selfEmployed('Самозанятый', 'Режим самозанятых (замена патента)'),
  simplified('Упрощёнка', 'Упрощённая декларация (910)'),
  general('ОУР', 'Общеустановленный режим');

  const TaxRegime(this.shortName, this.fullName);
  final String shortName;
  final String fullName;
}
