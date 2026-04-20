import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/employee.dart';
import '../services/hive_service.dart';

const _uuid = Uuid();
const _storageKey = 'employees';

class EmployeesNotifier extends StateNotifier<List<Employee>> {
  EmployeesNotifier() : super(const []) {
    _load();
  }

  void _load() {
    final box = HiveService.settings;
    final raw = box.get(_storageKey) as String?;
    if (raw == null || raw.isEmpty) {
      state = const [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      state = const [];
    }
  }

  Future<void> _persist() async {
    final box = HiveService.settings;
    final encoded = jsonEncode(state.map((e) => e.toJson()).toList());
    await box.put(_storageKey, encoded);
  }

  Future<Employee> add({
    required String name,
    String? iin,
    String? position,
    required double monthlySalary,
    required DateTime hireDate,
    DateTime? terminationDate,
    bool bornBefore1975 = false,
  }) async {
    final emp = Employee(
      id: _uuid.v4(),
      name: name,
      iin: iin,
      position: position,
      monthlySalary: monthlySalary,
      hireDate: hireDate,
      terminationDate: terminationDate,
      bornBefore1975: bornBefore1975,
    );
    state = [...state, emp];
    await _persist();
    return emp;
  }

  Future<void> update(Employee emp) async {
    state = [for (final e in state) if (e.id == emp.id) emp else e];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }
}

final employeesProvider =
    StateNotifierProvider<EmployeesNotifier, List<Employee>>((ref) {
  return EmployeesNotifier();
});

/// Только активные сейчас сотрудники.
final activeEmployeesProvider = Provider<List<Employee>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(employeesProvider)
      .where((e) => e.isActiveInMonth(now.year, now.month))
      .toList();
});

/// Сводка ФОТ за конкретное полугодие — для автозаполнения формы 910.
final payrollSummaryProvider =
    Provider.family<PayrollPeriodSummary, ({int year, int halfYear})>(
  (ref, args) {
    final employees = ref.watch(employeesProvider);
    return PayrollPeriodSummary.fromEmployees(
      employees,
      year: args.year,
      halfYear: args.halfYear,
    );
  },
);
