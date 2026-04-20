import 'package:intl/intl.dart';

/// Сотрудник ИП/ТОО.
/// Хранится локально в Hive как JSON-список под ключом `employees`
/// в settings box.
class Employee {
  final String id;
  final String name;
  final String? iin;
  final String? position;
  final double monthlySalary;
  final DateTime hireDate;
  final DateTime? terminationDate;
  final bool bornBefore1975;

  const Employee({
    required this.id,
    required this.name,
    this.iin,
    this.position,
    required this.monthlySalary,
    required this.hireDate,
    this.terminationDate,
    this.bornBefore1975 = false,
  });

  /// Активен ли сотрудник в указанном месяце (year, month).
  /// Считается активным, если hireDate <= конца месяца и (terminationDate == null || terminationDate >= начала месяца).
  bool isActiveInMonth(int year, int month) {
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);
    if (hireDate.isAfter(monthEnd)) return false;
    final term = terminationDate;
    if (term != null && term.isBefore(monthStart)) return false;
    return true;
  }

  Employee copyWith({
    String? name,
    String? iin,
    String? position,
    double? monthlySalary,
    DateTime? hireDate,
    DateTime? terminationDate,
    bool? bornBefore1975,
    bool clearTermination = false,
  }) {
    return Employee(
      id: id,
      name: name ?? this.name,
      iin: iin ?? this.iin,
      position: position ?? this.position,
      monthlySalary: monthlySalary ?? this.monthlySalary,
      hireDate: hireDate ?? this.hireDate,
      terminationDate: clearTermination ? null : (terminationDate ?? this.terminationDate),
      bornBefore1975: bornBefore1975 ?? this.bornBefore1975,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iin': iin,
        'position': position,
        'monthlySalary': monthlySalary,
        'hireDate': hireDate.toIso8601String(),
        'terminationDate': terminationDate?.toIso8601String(),
        'bornBefore1975': bornBefore1975,
      };

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id: json['id'] as String,
        name: json['name'] as String,
        iin: json['iin'] as String?,
        position: json['position'] as String?,
        monthlySalary: (json['monthlySalary'] as num?)?.toDouble() ?? 0,
        hireDate: DateTime.parse(json['hireDate'] as String),
        terminationDate: json['terminationDate'] != null
            ? DateTime.parse(json['terminationDate'] as String)
            : null,
        bornBefore1975: json['bornBefore1975'] as bool? ?? false,
      );
}

/// Сводка по ФОТ за период (для автозаполнения формы 910).
class PayrollPeriodSummary {
  /// Среднесписочная численность: среднее кол-во активных сотрудников по месяцам периода.
  final double avgHeadcount;

  /// Средний ежемесячный ФОТ: сумма зарплат активных сотрудников / кол-во месяцев.
  final double avgMonthlyFot;

  /// Средняя зарплата на работника (avgMonthlyFot / avgHeadcount).
  final double avgWagePerWorker;

  /// Активных сотрудников на конец периода (для 910.00.003 как fallback).
  final int endHeadcount;

  final int monthsInPeriod;

  const PayrollPeriodSummary({
    required this.avgHeadcount,
    required this.avgMonthlyFot,
    required this.avgWagePerWorker,
    required this.endHeadcount,
    required this.monthsInPeriod,
  });

  bool get hasData => avgHeadcount > 0;

  static const empty = PayrollPeriodSummary(
    avgHeadcount: 0,
    avgMonthlyFot: 0,
    avgWagePerWorker: 0,
    endHeadcount: 0,
    monthsInPeriod: 0,
  );

  /// Построить сводку по списку сотрудников и периоду (полугодие).
  factory PayrollPeriodSummary.fromEmployees(
    List<Employee> employees, {
    required int year,
    required int halfYear,
  }) {
    final startMonth = halfYear == 1 ? 1 : 7;
    final endMonth = halfYear == 1 ? 6 : 12;
    final monthsCount = endMonth - startMonth + 1;

    int headcountMonthsSum = 0;
    double fotMonthsSum = 0;

    for (var m = startMonth; m <= endMonth; m++) {
      final active = employees.where((e) => e.isActiveInMonth(year, m));
      headcountMonthsSum += active.length;
      fotMonthsSum += active.fold(0.0, (s, e) => s + e.monthlySalary);
    }

    final avgHeadcount = headcountMonthsSum / monthsCount;
    final avgMonthlyFot = fotMonthsSum / monthsCount;
    final avgWage = avgHeadcount > 0 ? avgMonthlyFot / avgHeadcount : 0.0;

    final endHeadcount =
        employees.where((e) => e.isActiveInMonth(year, endMonth)).length;

    return PayrollPeriodSummary(
      avgHeadcount: avgHeadcount,
      avgMonthlyFot: avgMonthlyFot,
      avgWagePerWorker: avgWage,
      endHeadcount: endHeadcount,
      monthsInPeriod: monthsCount,
    );
  }
}

/// Форматирует дату в дд.мм.гггг
String formatShortDate(DateTime date) =>
    DateFormat('dd.MM.yyyy', 'ru_RU').format(date);
