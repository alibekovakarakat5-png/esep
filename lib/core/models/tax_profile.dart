/// Налоговый профиль компании пользователя.
/// Хранится на бэкенде в `company_tax_profile`, синхронизируется при логине.
/// Используется для рекомендации КБК и подсказок Консультанта.
enum EntityType {
  ip('ip', 'ИП'),
  too('too', 'ТОО'),
  individual('individual', 'Физлицо');

  final String code;
  final String label;
  const EntityType(this.code, this.label);

  static EntityType fromCode(String? c) {
    if (c == 'too') return EntityType.too;
    if (c == 'individual') return EntityType.individual;
    return EntityType.ip;
  }
}

enum TaxRegimeKind {
  esp('esp', 'ЕСП'),
  selfEmployed('self_employed', 'Самозанятый'),
  simplified910('910', 'Упрощёнка (910)'),
  general('oyr', 'ОУР (общеустановленный)'),
  retail('retail', 'Розничный налог');

  final String code;
  final String label;
  const TaxRegimeKind(this.code, this.label);

  static TaxRegimeKind? fromCode(String? c) {
    if (c == null) return null;
    for (final r in TaxRegimeKind.values) {
      if (r.code == c) return r;
    }
    return null;
  }
}

enum SizeCategory {
  small('small', 'Малый бизнес',
      'до 100 сотрудников и до 300 000 МРП оборота в год'),
  medium('medium', 'Средний бизнес',
      'до 250 сотрудников и до 3 000 000 МРП оборота в год'),
  large('large', 'Крупный бизнес',
      'свыше 250 сотрудников или свыше 3 000 000 МРП оборота');

  final String code;
  final String label;
  final String description;
  const SizeCategory(this.code, this.label, this.description);

  static SizeCategory? fromCode(String? c) {
    if (c == null) return null;
    for (final s in SizeCategory.values) {
      if (s.code == c) return s;
    }
    return null;
  }
}

class TaxProfile {
  final EntityType entityType;
  final TaxRegimeKind? regime;
  final SizeCategory? sizeCategory;
  final bool hasEmployees;
  final bool isVatPayer;
  final int employeesCount;
  final num? annualRevenue;
  final bool exists;  // сохранён ли в БД

  const TaxProfile({
    required this.entityType,
    this.regime,
    this.sizeCategory,
    this.hasEmployees = false,
    this.isVatPayer = false,
    this.employeesCount = 0,
    this.annualRevenue,
    this.exists = false,
  });

  factory TaxProfile.fromJson(Map<String, dynamic> j) => TaxProfile(
        entityType: EntityType.fromCode(j['entity_type'] as String?),
        regime: TaxRegimeKind.fromCode(j['regime'] as String?),
        sizeCategory: SizeCategory.fromCode(j['size_category'] as String?),
        hasEmployees: (j['has_employees'] as bool?) ?? false,
        isVatPayer:   (j['is_vat_payer']  as bool?) ?? false,
        employeesCount: (j['employees_count'] is num)
            ? (j['employees_count'] as num).toInt()
            : 0,
        annualRevenue: j['annual_revenue'] is num ? j['annual_revenue'] as num : null,
        exists: (j['exists'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'entity_type':     entityType.code,
        'regime':          regime?.code,
        'size_category':   sizeCategory?.code,
        'has_employees':   hasEmployees,
        'is_vat_payer':    isVatPayer,
        'employees_count': employeesCount,
        'annual_revenue':  annualRevenue,
      };

  TaxProfile copyWith({
    EntityType? entityType,
    TaxRegimeKind? regime,
    Object? sizeCategory = _Sentinel.notSet,
    bool? hasEmployees,
    bool? isVatPayer,
    int? employeesCount,
    Object? annualRevenue = _Sentinel.notSet,
  }) {
    return TaxProfile(
      entityType: entityType ?? this.entityType,
      regime:     regime ?? this.regime,
      sizeCategory: identical(sizeCategory, _Sentinel.notSet)
          ? this.sizeCategory
          : sizeCategory as SizeCategory?,
      hasEmployees:  hasEmployees ?? this.hasEmployees,
      isVatPayer:    isVatPayer ?? this.isVatPayer,
      employeesCount: employeesCount ?? this.employeesCount,
      annualRevenue: identical(annualRevenue, _Sentinel.notSet)
          ? this.annualRevenue
          : annualRevenue as num?,
      exists: exists,
    );
  }

  /// Что писать в подсказке: "ИП на 910", "ТОО (средний бизнес) на ОУР".
  String get humanLabel {
    final parts = <String>[entityType.label];
    if (entityType == EntityType.too && sizeCategory != null) {
      parts.add('(${sizeCategory!.label.toLowerCase()})');
    }
    if (regime != null) parts.add('на ${regime!.label}');
    return parts.join(' ');
  }
}

enum _Sentinel { notSet }
