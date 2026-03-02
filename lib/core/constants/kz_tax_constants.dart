/// Константы налогового законодательства Казахстана
/// Обновляются ежегодно — не хардкодить в бизнес-логике!
library kz_tax_constants;

class KzTax {
  KzTax._();

  // ─── МРП (Месячный расчётный показатель) ─────────────────────────────────
  /// МРП на 2025 год
  static const double mrp2025 = 3932.0;

  /// МРП на 2026 год (обновить после утверждения бюджета)
  static const double mrp2026 = 4205.0; // предварительно

  static double get currentMrp => mrp2025;

  // ─── МЗП (Минимальная заработная плата) ──────────────────────────────────
  static const double mzp2025 = 85000.0;
  static double get currentMzp => mzp2025;

  // ─── Упрощённая декларация (Форма 910) ───────────────────────────────────

  /// Максимальный доход за полугодие (24 038 МРП)
  static double get simplified910HalfYearLimit => currentMrp * 24038;

  /// Максимальный доход за год
  static double get simplified910YearLimit => simplified910HalfYearLimit * 2;

  /// ИПН: 1.5% от дохода
  static const double ipnRate = 0.015;

  /// СН: 1.5% от дохода
  static const double snRate = 0.015;

  /// Суммарная ставка 910: 3%
  static const double simplified910TotalRate = ipnRate + snRate;

  /// ОПВ: 10% от дохода, но не более 50 МЗП
  static const double opvRate = 0.10;
  static double get opvMaxBase => currentMzp * 50;

  /// СО: 3.5% от (доход − ОПВ), не более 7 МЗП
  static const double soRate = 0.035;
  static double get soMaxBase => currentMzp * 7;

  // ─── ЕСП (Единый совокупный платёж) ─────────────────────────────────────

  /// Лимит дохода: 1 175 МРП в год
  static double get espYearLimit => currentMrp * 1175;

  /// Платёж: 1 МРП/мес в городе
  static double get espMonthlyCity => currentMrp;

  /// Платёж: 0.5 МРП/мес в селе
  static double get espMonthlyRural => currentMrp * 0.5;

  // ─── Патент ──────────────────────────────────────────────────────────────

  /// Лимит дохода: 3 528 МРП в год
  static double get patentYearLimit => currentMrp * 3528;

  /// Ставка: 1% от заявленного дохода
  static const double patentRate = 0.01;

  // ─── НДС ─────────────────────────────────────────────────────────────────

  /// Порог обязательной регистрации по НДС: 20 000 МРП за 12 мес
  static double get vatRegistrationThreshold => currentMrp * 20000;

  /// Стандартная ставка НДС
  static const double vatRate = 0.12;

  // ─── Вспомогательные методы ──────────────────────────────────────────────

  /// Рассчитать налоги по упрощёнке за период
  static TaxCalculation calculate910(double income) {
    final ipn = income * ipnRate;
    final sn = income * snRate;
    final opvBase = income.clamp(0, opvMaxBase);
    final opv = opvBase * opvRate;
    final soBase = (income - opv).clamp(0, soMaxBase);
    final so = soBase * soRate;
    return TaxCalculation(
      income: income,
      ipn: ipn,
      sn: sn,
      opv: opv,
      so: so,
      total: ipn + sn + opv + so,
    );
  }

  /// Рассчитать налог по патенту
  static double calculatePatent(double declaredIncome) =>
      declaredIncome * patentRate;
}

/// Результат расчёта налогов по 910 форме
class TaxCalculation {
  final double income;
  final double ipn;
  final double sn;
  final double opv;
  final double so;
  final double total;

  const TaxCalculation({
    required this.income,
    required this.ipn,
    required this.sn,
    required this.opv,
    required this.so,
    required this.total,
  });

  double get effectiveRate => income > 0 ? total / income : 0;
}

/// Налоговые режимы ИП в Казахстане
enum TaxRegime {
  esp('ЕСП', 'Единый совокупный платёж'),
  patent('Патент', 'Патент'),
  simplified('Упрощёнка', 'Упрощённая декларация (910)'),
  general('ОУР', 'Общеустановленный режим');

  const TaxRegime(this.shortName, this.fullName);
  final String shortName;
  final String fullName;
}
