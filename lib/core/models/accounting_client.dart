/// Модель клиента бухгалтера (ИП или ТОО на обслуживании)
library accounting_client;

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ClientEntityType { ip, too }

extension ClientEntityTypeExt on ClientEntityType {
  String get label => this == ClientEntityType.ip ? 'ИП' : 'ТОО';
}

enum ClientTaxRegime { esp, patent, simplified910, our }

extension ClientTaxRegimeExt on ClientTaxRegime {
  String get label => switch (this) {
        ClientTaxRegime.esp         => 'ЕСП',
        ClientTaxRegime.patent      => 'Патент',
        ClientTaxRegime.simplified910 => 'Упрощёнка',
        ClientTaxRegime.our         => 'ОУР',
      };
}

// ── Employee ──────────────────────────────────────────────────────────────────

class Employee {
  final String id;
  final String name;
  final double salary;

  const Employee({required this.id, required this.name, required this.salary});

  factory Employee.fromJson(Map<dynamic, dynamic> j) => Employee(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        salary: _toDouble(j['salary']),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'salary': salary};

  Employee copyWith({String? id, String? name, double? salary}) => Employee(
        id: id ?? this.id,
        name: name ?? this.name,
        salary: salary ?? this.salary,
      );
}

/// Числа из Postgres (NUMERIC) приезжают строкой — принимаем оба варианта.
double _toDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

// ── Document checklist item ───────────────────────────────────────────────────

class DocChecklistItem {
  final String id;
  final String label;
  final bool received;

  const DocChecklistItem({
    required this.id,
    required this.label,
    this.received = false,
  });

  factory DocChecklistItem.fromJson(Map<dynamic, dynamic> j) => DocChecklistItem(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        received: j['received'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'label': label, 'received': received};

  DocChecklistItem copyWith({String? id, String? label, bool? received}) =>
      DocChecklistItem(
        id: id ?? this.id,
        label: label ?? this.label,
        received: received ?? this.received,
      );
}

// ── Accounting Client ─────────────────────────────────────────────────────────

class AccountingClient {
  final String id;
  final String name;
  final String binOrIin;
  final ClientEntityType entityType;
  final ClientTaxRegime regime;
  final List<Employee> employees;
  final double monthlyFee;
  final bool feeReceivedThisMonth;
  final List<DocChecklistItem> checklist;
  final String? notes;
  final bool isActive;

  /// Телефон клиента — по нему бот сбора документов пишет в WhatsApp.
  final String? phone;

  const AccountingClient({
    required this.id,
    required this.name,
    required this.binOrIin,
    required this.entityType,
    required this.regime,
    this.employees = const [],
    this.monthlyFee = 0,
    this.feeReceivedThisMonth = false,
    this.checklist = const [],
    this.notes,
    this.isActive = true,
    this.phone,
  });

  int get missingDocs => checklist.where((d) => !d.received).length;
  bool get allDocsReceived => checklist.isEmpty || checklist.every((d) => d.received);

  /// Контракт с сервером — snake_case, как у transactions/invoices.
  factory AccountingClient.fromJson(Map<dynamic, dynamic> j) => AccountingClient(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        binOrIin: j['bin_or_iin'] as String? ?? '',
        entityType: ClientEntityType.values.firstWhere(
          (e) => e.name == j['entity_type'],
          orElse: () => ClientEntityType.ip,
        ),
        regime: ClientTaxRegime.values.firstWhere(
          (r) => r.name == j['regime'],
          orElse: () => ClientTaxRegime.simplified910,
        ),
        monthlyFee: _toDouble(j['monthly_fee']),
        feeReceivedThisMonth: j['fee_received_this_month'] as bool? ?? false,
        notes: j['notes'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        phone: j['phone'] as String?,
        employees: (j['employees'] as List<dynamic>? ?? const [])
            .map((e) => Employee.fromJson(e as Map<dynamic, dynamic>))
            .toList(),
        checklist: (j['checklist'] as List<dynamic>? ?? const [])
            .map((d) => DocChecklistItem.fromJson(d as Map<dynamic, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bin_or_iin': binOrIin,
        'entity_type': entityType.name,
        'regime': regime.name,
        'monthly_fee': monthlyFee,
        'fee_received_this_month': feeReceivedThisMonth,
        'notes': notes,
        'is_active': isActive,
        'phone': phone,
        'employees': employees.map((e) => e.toJson()).toList(),
        'checklist': checklist.map((d) => d.toJson()).toList(),
      };

  AccountingClient copyWith({
    String? id,
    String? name,
    String? binOrIin,
    ClientEntityType? entityType,
    ClientTaxRegime? regime,
    List<Employee>? employees,
    double? monthlyFee,
    bool? feeReceivedThisMonth,
    List<DocChecklistItem>? checklist,
    String? notes,
    bool? isActive,
    String? phone,
  }) =>
      AccountingClient(
        id: id ?? this.id,
        name: name ?? this.name,
        binOrIin: binOrIin ?? this.binOrIin,
        entityType: entityType ?? this.entityType,
        regime: regime ?? this.regime,
        employees: employees ?? this.employees,
        monthlyFee: monthlyFee ?? this.monthlyFee,
        feeReceivedThisMonth: feeReceivedThisMonth ?? this.feeReceivedThisMonth,
        checklist: checklist ?? this.checklist,
        notes: notes ?? this.notes,
        isActive: isActive ?? this.isActive,
        phone: phone ?? this.phone,
      );
}

// ── Client Deadline ───────────────────────────────────────────────────────────

class ClientDeadline {
  final String clientId;
  final String clientName;
  final String type;   // 'social', '910', '200', '700', 'esp', 'patent'
  final String label;
  final DateTime date;

  const ClientDeadline({
    required this.clientId,
    required this.clientName,
    required this.type,
    required this.label,
    required this.date,
  });

  int get daysLeft => date.difference(DateTime.now()).inDays;
  bool get isUrgent => daysLeft <= 3;
  bool get isWarning => daysLeft <= 7;
  bool get isPast => daysLeft < 0;
}

// ── Employee Social Calculation ───────────────────────────────────────────────

class EmployeeSocialCalc {
  final Employee employee;
  final double opv;       // ОПВ — пенсионные (из з/п сотрудника, 10%)
  final double ipn;       // ИПН — подоходный (из з/п, ~10%)
  final double opvr;      // ОПВР — пенсионные работодателя (3.5% в 2026)
  final double so;        // СО — соцотчисления работодателя (5%)
  final double vosms;     // ВОСМС работодателя (2%)
  final double vosmsSelf; // ВОСМС сотрудника (1%)

  const EmployeeSocialCalc({
    required this.employee,
    required this.opv,
    required this.ipn,
    required this.opvr,
    required this.so,
    required this.vosms,
    required this.vosmsSelf,
  });

  /// Удержания из зарплаты сотрудника
  double get employeeDeductions => opv + ipn + vosmsSelf;

  /// На руки
  double get netSalary => employee.salary - employeeDeductions;

  /// Расходы работодателя сверх зарплаты
  double get employerExtra => opvr + so + vosms;

  /// Полная стоимость для работодателя
  double get totalCost => employee.salary + employerExtra;
}
