/// Расчёт диагностики «Что изменилось для меня в 2026».
///
/// Сравнивает налоговую нагрузку по ставкам 2025 (старый НК) и 2026
/// (Закон 214-VIII «О налогах»). Формирует персональный список изменений.
///
/// Источники ставок:
/// - 2025: Старый НК РК + Закон о бюджете 2025 (МРП 3 932, МЗП 85 000)
/// - 2026: Новый НК РК 214-VIII + Закон о бюджете 2026 (МРП 4 325, МЗП 85 000)
library diagnosis_service;

import 'dart:math';

import '../models/diagnosis.dart';
import '../models/tax_profile.dart';

/// Снимок ставок одного года для воспроизводимого сравнения
class _TaxYearRates {
  // Базовые показатели
  final double mrp;
  final double mzp;

  // 910 (упрощёнка)
  final double rate910; // суммарная ставка

  // Самозанятые
  final double rateSelfEmployed;
  final double selfEmpYearLimitMrp;

  // Соцплатежи "за себя" (% от 1 МЗП)
  final double opvRate;
  final double opvrRate;
  final double soRate;
  final double vosmsRate;
  final double vosmsBaseMult; // ВОСМС = % × N МЗП

  // Соцплатежи работника
  final double eeOpvRate;
  final double eeVosmsRate;

  // Соцплатежи работодателя
  final double employerOpvrRate;
  final double employerSoRate;
  final double employerVosmsRate;

  // ОУР: ИПН и КПН
  final double ipnBase;        // 10% базовая ставка
  final double ipnHigh;        // повышенная (только 2026)
  final double ipnHighMrpStop; // порог в МРП (только 2026)
  final double ipnDeductionMrp;
  final double kpnRate;        // 20% КПН для ТОО
  final double socialTaxTooRate; // СН для ТОО

  // НДС
  final double vatRate;
  final double vatThresholdMrp;

  const _TaxYearRates({
    required this.mrp,
    required this.mzp,
    required this.rate910,
    required this.rateSelfEmployed,
    required this.selfEmpYearLimitMrp,
    required this.opvRate,
    required this.opvrRate,
    required this.soRate,
    required this.vosmsRate,
    required this.vosmsBaseMult,
    required this.eeOpvRate,
    required this.eeVosmsRate,
    required this.employerOpvrRate,
    required this.employerSoRate,
    required this.employerVosmsRate,
    required this.ipnBase,
    required this.ipnHigh,
    required this.ipnHighMrpStop,
    required this.ipnDeductionMrp,
    required this.kpnRate,
    required this.socialTaxTooRate,
    required this.vatRate,
    required this.vatThresholdMrp,
  });

  static const rates2025 = _TaxYearRates(
    mrp: 3932,
    mzp: 85000,
    rate910: 0.03,        // 3% (1% ИПН + 1.5% СН + 0.5% от старой схемы 100% / прочее)
    rateSelfEmployed: 0.04, // патент/самозан был ~4% эффективно
    selfEmpYearLimitMrp: 1175,
    opvRate: 0.10,
    opvrRate: 0.025,      // ОПВР 2025 = 2.5%
    soRate: 0.035,        // СО 2025 = 3.5%
    vosmsRate: 0.05,
    vosmsBaseMult: 1.4,
    eeOpvRate: 0.10,
    eeVosmsRate: 0.02,
    employerOpvrRate: 0.025,
    employerSoRate: 0.035,
    employerVosmsRate: 0.03,
    ipnBase: 0.10,
    ipnHigh: 0.10,         // прогрессии не было
    ipnHighMrpStop: 1e9,   // никогда не наступает
    ipnDeductionMrp: 14,
    kpnRate: 0.20,
    socialTaxTooRate: 0.095, // СН 9.5% − СО (упрощённо берём 9.5% от базы)
    vatRate: 0.12,
    vatThresholdMrp: 20000,
  );

  static const rates2026 = _TaxYearRates(
    mrp: 4325,
    mzp: 85000,
    rate910: 0.04,
    rateSelfEmployed: 0.04,
    selfEmpYearLimitMrp: 3600,
    opvRate: 0.10,
    opvrRate: 0.035,
    soRate: 0.05,
    vosmsRate: 0.05,
    vosmsBaseMult: 1.4,
    eeOpvRate: 0.10,
    eeVosmsRate: 0.02,
    employerOpvrRate: 0.035,
    employerSoRate: 0.05,
    employerVosmsRate: 0.03,
    ipnBase: 0.10,
    ipnHigh: 0.15,
    ipnHighMrpStop: 8500,
    ipnDeductionMrp: 30,
    kpnRate: 0.20,
    socialTaxTooRate: 0.06,
    vatRate: 0.16,
    vatThresholdMrp: 10000,
  );
}

class DiagnosisService {
  DiagnosisService._();

  /// Главный метод — формирует отчёт по ответам пользователя
  static DiagnosisReport calculate(DiagnosisAnswers ans) {
    final tax2025 = _calculateAnnualTax(ans, _TaxYearRates.rates2025);
    final tax2026 = _calculateAnnualTax(ans, _TaxYearRates.rates2026);

    final changes = _buildChanges(ans, _TaxYearRates.rates2025, _TaxYearRates.rates2026);
    final recs = _buildRecommendations(ans, tax2026 - tax2025);

    return DiagnosisReport(
      answers: ans,
      annualTax2025: tax2025,
      annualTax2026: tax2026,
      changes: changes,
      recommendations: recs,
    );
  }

  // ── Расчёт годовой нагрузки ───────────────────────────────────────────────

  static double _calculateAnnualTax(DiagnosisAnswers ans, _TaxYearRates r) {
    double total = 0;

    // ── Основной налог по режиму ─────────────────────────────────────────
    switch (ans.regime) {
      case TaxRegimeKind.simplified910:
        total += ans.annualRevenue * r.rate910;
        break;
      case TaxRegimeKind.selfEmployed:
      case TaxRegimeKind.esp:
        total += ans.annualRevenue * r.rateSelfEmployed;
        break;
      case TaxRegimeKind.general:
      case TaxRegimeKind.retail:
        if (ans.entityType == EntityType.too) {
          // ТОО на ОУР: КПН с прибыли (упрощённо считаем 20% доход × 30% маржа)
          final taxableIncome = ans.annualRevenue * 0.30;
          total += taxableIncome * r.kpnRate;
        } else {
          // ИП на ОУР: прогрессивный ИПН
          final annual = ans.annualRevenue * 0.7; // после вычетов
          final threshold = r.mrp * r.ipnHighMrpStop;
          if (annual <= threshold) {
            total += annual * r.ipnBase;
          } else {
            total += threshold * r.ipnBase +
                (annual - threshold) * r.ipnHigh;
          }
        }
        break;
    }

    // ── НДС (только ОУР и плательщики) ─────────────────────────────────────
    final vatThreshold = r.mrp * r.vatThresholdMrp;
    if (ans.isVatPayer &&
        (ans.regime == TaxRegimeKind.general || ans.regime == TaxRegimeKind.retail) &&
        ans.annualRevenue > vatThreshold) {
      // Упрощённо: НДС начисляется на 60% оборота (остальное — закупки с НДС в зачёт)
      total += ans.annualRevenue * 0.6 * r.vatRate;
    }

    // ── Соцплатежи "за себя" (только ИП, кроме самозанятых) ───────────────
    if (ans.entityType == EntityType.ip && ans.regime != TaxRegimeKind.selfEmployed) {
      final monthlyOpv = r.mzp * r.opvRate;
      final monthlySo = r.mzp * r.soRate;
      final monthlyVosms = r.mzp * r.vosmsBaseMult * r.vosmsRate;
      total += (monthlyOpv + monthlySo + monthlyVosms) * 12;
    }

    // ── Соцплатежи за сотрудников ──────────────────────────────────────────
    if (ans.hasEmployees && ans.employeesCount > 0) {
      final monthlyPayroll = ans.averageSalary;
      // С работника (это удержание из зарплаты, но платит работодатель)
      final eeOpv = monthlyPayroll * r.eeOpvRate;
      final eeVosms = monthlyPayroll * r.eeVosmsRate;
      // За работника
      final emOpvr = monthlyPayroll * r.employerOpvrRate;
      final emSo = monthlyPayroll * r.employerSoRate;
      final emVosms = monthlyPayroll * r.employerVosmsRate;
      // Соцналог (только для ТОО, для ИП на 910 = 0)
      double sn = 0;
      if (ans.entityType == EntityType.too) {
        sn = monthlyPayroll * r.socialTaxTooRate;
      }
      final perEmployeeMonth = eeOpv + eeVosms + emOpvr + emSo + emVosms + sn;
      total += perEmployeeMonth * 12 * ans.employeesCount;
    }

    return max(0, total);
  }

  // ── Список изменений ──────────────────────────────────────────────────────

  static List<TaxChange> _buildChanges(
      DiagnosisAnswers ans, _TaxYearRates r25, _TaxYearRates r26) {
    final out = <TaxChange>[];

    // ── МРП ──────────────────────────────────────────────────────────────
    out.add(TaxChange(
      title: 'МРП вырос: 3 932 → 4 325 ₸ (+10%)',
      description:
          'Растут штрафы, лимиты, фиксированные платежи (например, ЕСП). '
          'Зато и налоговые вычеты ИПН тоже выше.',
      direction: ChangeDirection.neutral,
      iconName: 'mrp',
    ));

    // ── 910 — ставка ────────────────────────────────────────────────────
    if (ans.regime == TaxRegimeKind.simplified910) {
      final delta = ans.annualRevenue * (r26.rate910 - r25.rate910);
      out.add(TaxChange(
        title: 'Упрощёнка 910: ставка 3% → 4%',
        description:
            'С 2026 года базовая ставка по форме 910 выросла с 3% до 4% от дохода. '
            'Маслихат может скорректировать ±50% (от 2% до 6%).',
        annualDelta: delta,
        direction: delta > 0 ? ChangeDirection.negative : ChangeDirection.neutral,
        iconName: 'percent',
      ));

      // Лимит сотрудников
      out.add(const TaxChange(
        title: 'Лимит сотрудников снят',
        description:
            'Раньше упрощёнка ограничивалась 30 сотрудниками. С 2026 года — без лимита.',
        direction: ChangeDirection.positive,
        iconName: 'group',
      ));

      // Освобождение от НДС
      out.add(const TaxChange(
        title: 'Упрощёнка полностью освобождена от НДС',
        description:
            'С 2026 года ИП и ТОО на упрощёнке не платят НДС, даже если оборот превысил порог. '
            'Это огромная экономия для растущих бизнесов.',
        direction: ChangeDirection.positive,
        iconName: 'shield',
      ));
    }

    // ── Самозанятые ─────────────────────────────────────────────────────
    if (ans.regime == TaxRegimeKind.selfEmployed || ans.regime == TaxRegimeKind.esp) {
      out.add(const TaxChange(
        title: 'Патент ликвидирован → Самозанятые 4%',
        description:
            'С 01.01.2026 патентного режима больше нет. Вместо него — режим '
            'самозанятых: 4% от дохода (1% ИПН + 2% ОПВ + 1% ВОСМС). '
            'Лимит дохода — 3 600 МРП в год (~15.6 млн ₸).',
        direction: ChangeDirection.neutral,
        iconName: 'self',
      ));
    }

    // ── НДС ─────────────────────────────────────────────────────────────
    if (ans.isVatPayer && (ans.regime == TaxRegimeKind.general || ans.regime == TaxRegimeKind.retail)) {
      final vatBase = ans.annualRevenue * 0.6;
      final delta = vatBase * (r26.vatRate - r25.vatRate);
      out.add(TaxChange(
        title: 'НДС: 12% → 16%',
        description:
            'Ставка НДС выросла с 12% до 16%. Параллельно порог постановки на учёт '
            'снизился с 20 000 МРП до 10 000 МРП (~43.25 млн ₸/год) — попадание стало вдвое чаще.',
        annualDelta: delta,
        direction: ChangeDirection.negative,
        iconName: 'vat',
      ));
    } else if (ans.regime == TaxRegimeKind.general || ans.regime == TaxRegimeKind.retail) {
      out.add(const TaxChange(
        title: 'Порог НДС снизился: 20 000 МРП → 10 000 МРП',
        description:
            'Если ваш оборот близок к 43 млн ₸/год — есть риск автоматически '
            'попасть в плательщики НДС. Следите за оборотом.',
        direction: ChangeDirection.neutral,
        iconName: 'vat',
      ));
    }

    // ── ОПВР за сотрудников ──────────────────────────────────────────────
    if (ans.hasEmployees && ans.employeesCount > 0) {
      final yearlyPayroll = ans.averageSalary * 12 * ans.employeesCount;
      final delta = yearlyPayroll * (r26.employerOpvrRate - r25.employerOpvrRate);
      out.add(TaxChange(
        title: 'ОПВР работодателя: 2.5% → 3.5%',
        description:
            'Обязательные пенсионные взносы работодателя за каждого сотрудника '
            'выросли на 1 процентный пункт.',
        annualDelta: delta,
        direction: delta > 0 ? ChangeDirection.negative : ChangeDirection.neutral,
        iconName: 'opvr',
      ));

      final deltaSo = yearlyPayroll * (r26.employerSoRate - r25.employerSoRate);
      out.add(TaxChange(
        title: 'СО за сотрудников: 3.5% → 5%',
        description: 'Социальные отчисления за работников выросли на 1.5 п.п.',
        annualDelta: deltaSo,
        direction: ChangeDirection.negative,
        iconName: 'so',
      ));

      if (ans.entityType == EntityType.too) {
        // СН упростили для ТОО — было 9.5% − СО, стало 6% без вычета
        final delta25 = yearlyPayroll * (r25.socialTaxTooRate - r25.employerSoRate);
        final delta26 = yearlyPayroll * r26.socialTaxTooRate;
        out.add(TaxChange(
          title: 'СН для ТОО упрощён: 9.5% (−СО) → 6% от ФОТ',
          description:
              'Соцналог для ТОО теперь считается проще: 6% от ФОТ без вычета СО. '
              'Для большинства ТОО это снижение нагрузки.',
          annualDelta: delta26 - delta25,
          direction: (delta26 - delta25) <= 0
              ? ChangeDirection.positive
              : ChangeDirection.negative,
          iconName: 'sn',
        ));
      }
    }

    // ── ИПН прогрессивный (только для ОУР, ИП) ───────────────────────────
    if (ans.entityType == EntityType.ip && ans.regime == TaxRegimeKind.general) {
      out.add(const TaxChange(
        title: 'ИПН стал прогрессивным',
        description:
            'С 2026 года: 10% до 8 500 МРП (~36.8 млн ₸/год) и 15% свыше. '
            'Раньше была плоская ставка 10%. Базовый вычет вырос с 14 МРП до 30 МРП.',
        direction: ChangeDirection.neutral,
        iconName: 'progressive',
      ));
    }

    return out;
  }

  // ── Рекомендации ──────────────────────────────────────────────────────────

  static List<String> _buildRecommendations(
      DiagnosisAnswers ans, double totalDelta) {
    final out = <String>[];

    if (ans.regime == TaxRegimeKind.simplified910) {
      out.add('Проверьте региональный коэффициент маслихата — ставка 910 '
          'может быть от 2% до 6%, не везде ровно 4%.');
      out.add('Если планируете расти выше 30 сотрудников — теперь это можно '
          'без перехода на ОУР.');
    }

    if (ans.regime == TaxRegimeKind.general || ans.regime == TaxRegimeKind.retail) {
      out.add('Если оборот ≤ 600 000 МРП/год (~2.6 млрд ₸) — рассмотрите переход '
          'на упрощёнку 910: освобождение от НДС, ставка 4%, отчётность 2×/год.');
    }

    if (ans.hasEmployees && ans.employeesCount > 0) {
      out.add('Пересчитайте бюджет ФОТ на 2026: ОПВР +1 п.п., СО +1.5 п.п. '
          'для каждого сотрудника.');
    }

    if (totalDelta > 100000) {
      out.add('Налоговая нагрузка существенно выросла — Esep поможет сэкономить '
          'за счёт автоматических вычетов и подсказок по режимам.');
    } else if (totalDelta < -100000) {
      out.add('Хорошие новости: нагрузка снизилась. Esep напомнит вовремя '
          'все дедлайны, чтобы не получить пеню.');
    }

    out.add('Подключите автонапоминания в Esep — все дедлайны 910/200/300 '
        'и соцплатежей попадут в календарь.');

    return out;
  }
}
