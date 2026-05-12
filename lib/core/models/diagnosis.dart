/// Модели для онбординг-диагностики «Что изменилось для меня в 2026».
///
/// Цель — простыми вопросами собрать профиль пользователя и показать
/// персональный отчёт: какие пункты НК 2026 коснулись лично его и
/// сколько он заплатит больше/меньше по сравнению с 2025.
library diagnosis;

import 'tax_profile.dart';

/// Ответы пользователя из step-формы (минимально необходимые для расчёта)
class DiagnosisAnswers {
  /// ИП / ТОО / физлицо
  final EntityType entityType;

  /// Налоговый режим (упрощёнка / ОУР / ЕСП / самозанятый)
  final TaxRegimeKind regime;

  /// Есть ли наёмные сотрудники
  final bool hasEmployees;

  /// Сколько сотрудников (если есть)
  final int employeesCount;

  /// Средняя зарплата сотрудника, ₸/мес (для оценки ФОТ)
  final double averageSalary;

  /// Ориентировочный годовой доход, ₸
  final double annualRevenue;

  /// Плательщик НДС (актуально только для ОУР)
  final bool isVatPayer;

  /// Родился до 1975 (тогда ОПВР за себя не платит)
  final bool bornBefore1975;

  const DiagnosisAnswers({
    required this.entityType,
    required this.regime,
    this.hasEmployees = false,
    this.employeesCount = 0,
    this.averageSalary = 150000,
    required this.annualRevenue,
    this.isVatPayer = false,
    this.bornBefore1975 = false,
  });

  DiagnosisAnswers copyWith({
    EntityType? entityType,
    TaxRegimeKind? regime,
    bool? hasEmployees,
    int? employeesCount,
    double? averageSalary,
    double? annualRevenue,
    bool? isVatPayer,
    bool? bornBefore1975,
  }) =>
      DiagnosisAnswers(
        entityType: entityType ?? this.entityType,
        regime: regime ?? this.regime,
        hasEmployees: hasEmployees ?? this.hasEmployees,
        employeesCount: employeesCount ?? this.employeesCount,
        averageSalary: averageSalary ?? this.averageSalary,
        annualRevenue: annualRevenue ?? this.annualRevenue,
        isVatPayer: isVatPayer ?? this.isVatPayer,
        bornBefore1975: bornBefore1975 ?? this.bornBefore1975,
      );
}

/// Знак изменения — для подсветки в UI
enum ChangeDirection {
  /// Хорошо для пользователя (платит меньше / упрощено)
  positive,
  /// Плохо (платит больше)
  negative,
  /// Нейтрально (важно знать, но без денежного эффекта)
  neutral,
}

/// Одно изменение в НК 2026, касающееся пользователя
class TaxChange {
  /// Короткое название изменения
  final String title;

  /// Подробное описание (1-2 предложения)
  final String description;

  /// Дельта в тенге за год (положительная = пользователь платит больше,
  /// отрицательная = меньше). null если без денежного эффекта.
  final double? annualDelta;

  /// Направление: лучше/хуже/нейтрально
  final ChangeDirection direction;

  /// Иконка (имя Material icon)
  final String iconName;

  const TaxChange({
    required this.title,
    required this.description,
    this.annualDelta,
    required this.direction,
    required this.iconName,
  });
}

/// Полный отчёт диагностики
class DiagnosisReport {
  /// Ответы пользователя (для отображения «вы — ИП на 910 с N сотрудниками»)
  final DiagnosisAnswers answers;

  /// Расчётная налоговая нагрузка за год по ставкам 2025
  final double annualTax2025;

  /// Расчётная налоговая нагрузка за год по ставкам 2026
  final double annualTax2026;

  /// Список изменений касающихся пользователя
  final List<TaxChange> changes;

  /// Что делать (3-5 рекомендаций)
  final List<String> recommendations;

  const DiagnosisReport({
    required this.answers,
    required this.annualTax2025,
    required this.annualTax2026,
    required this.changes,
    required this.recommendations,
  });

  /// Дельта = 2026 − 2025. Положительная — заплатит больше.
  double get totalDelta => annualTax2026 - annualTax2025;

  bool get isWorseOff => totalDelta > 0;
  bool get isBetterOff => totalDelta < 0;

  /// Относительная разница в процентах
  double get deltaPercent =>
      annualTax2025 > 0 ? (totalDelta / annualTax2025) * 100 : 0;
}
