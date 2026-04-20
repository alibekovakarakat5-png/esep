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

  Employee copyWith({String? id, String? name, double? salary}) => Employee(
        id: id ?? this.id,
        name: name ?? this.name,
        salary: salary ?? this.salary,
      );
}

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
  });

  int get missingDocs => checklist.where((d) => !d.received).length;
  bool get allDocsReceived => checklist.isEmpty || checklist.every((d) => d.received);

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
