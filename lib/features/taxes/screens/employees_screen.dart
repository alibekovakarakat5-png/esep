import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/employee.dart';
import '../../../core/providers/employees_provider.dart';

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesProvider);
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Сотрудники')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref, null),
        icon: const Icon(Iconsax.add),
        label: const Text('Добавить'),
        backgroundColor: EsepColors.primary,
      ),
      body: employees.isEmpty
          ? _EmptyState(onAdd: () => _showEditor(context, ref, null))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _HeaderCard(employees: employees, fmt: fmt, now: now),
                const SizedBox(height: 12),
                for (final emp in employees)
                  _EmployeeTile(
                    employee: emp,
                    fmt: fmt,
                    now: now,
                    onTap: () => _showEditor(context, ref, emp),
                    onDelete: () => _confirmDelete(context, ref, emp),
                  ),
              ],
            ),
    );
  }

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref,
    Employee? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeEditor(existing: existing),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Employee emp,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить сотрудника?'),
        content: Text('${emp.name} будет удалён без возможности восстановления.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: EsepColors.expense),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(employeesProvider.notifier).remove(emp.id);
    }
  }
}

// ─── Header card ────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.employees,
    required this.fmt,
    required this.now,
  });
  final List<Employee> employees;
  final NumberFormat fmt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final active =
        employees.where((e) => e.isActiveInMonth(now.year, now.month)).toList();
    final totalFot = active.fold(0.0, (s, e) => s + e.monthlySalary);

    return Card(
      color: EsepColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Активные сейчас',
                    style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${active.length} чел.',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: EsepColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'ФОТ в месяц',
                  style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${fmt.format(totalFot)} ₸',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: EsepColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── List tile ──────────────────────────────────────────────────────────────

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({
    required this.employee,
    required this.fmt,
    required this.now,
    required this.onTap,
    required this.onDelete,
  });
  final Employee employee;
  final NumberFormat fmt;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final active = employee.isActiveInMonth(now.year, now.month);
    final statusColor = active ? EsepColors.income : EsepColors.textDisabled;
    final statusLabel = active ? 'Активен' : 'Уволен';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: EsepColors.primary.withValues(alpha: 0.1),
                child: Text(
                  employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: EsepColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (employee.position != null &&
                            employee.position!.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              employee.position!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: EsepColors.textSecondary,
                              ),
                            ),
                          ),
                          const Text(' · ',
                              style: TextStyle(color: EsepColors.textSecondary)),
                        ],
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${fmt.format(employee.monthlySalary)} ₸',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'в месяц',
                    style: TextStyle(fontSize: 11, color: EsepColors.textSecondary),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Iconsax.trash,
                    size: 18, color: EsepColors.textDisabled),
                onPressed: onDelete,
                tooltip: 'Удалить',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Iconsax.people,
                size: 64, color: EsepColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Нет сотрудников',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте сотрудников — и форма 910 будет заполняться автоматически',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Iconsax.add),
              label: const Text('Добавить первого'),
              style: FilledButton.styleFrom(backgroundColor: EsepColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Editor (add/edit) ──────────────────────────────────────────────────────

class _EmployeeEditor extends ConsumerStatefulWidget {
  const _EmployeeEditor({this.existing});
  final Employee? existing;

  @override
  ConsumerState<_EmployeeEditor> createState() => _EmployeeEditorState();
}

class _EmployeeEditorState extends ConsumerState<_EmployeeEditor> {
  late final TextEditingController _name;
  late final TextEditingController _iin;
  late final TextEditingController _position;
  late final TextEditingController _salary;
  late DateTime _hireDate;
  DateTime? _terminationDate;
  late bool _bornBefore1975;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _iin = TextEditingController(text: e?.iin ?? '');
    _position = TextEditingController(text: e?.position ?? '');
    _salary = TextEditingController(
      text: e != null && e.monthlySalary > 0
          ? e.monthlySalary.toStringAsFixed(0)
          : '',
    );
    _hireDate = e?.hireDate ?? DateTime.now();
    _terminationDate = e?.terminationDate;
    _bornBefore1975 = e?.bornBefore1975 ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _iin.dispose();
    _position.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите имя сотрудника')),
      );
      return;
    }
    final salary = double.tryParse(_salary.text.replaceAll(' ', '')) ?? 0;
    final notifier = ref.read(employeesProvider.notifier);

    final existing = widget.existing;
    if (existing == null) {
      await notifier.add(
        name: name,
        iin: _iin.text.trim().isEmpty ? null : _iin.text.trim(),
        position:
            _position.text.trim().isEmpty ? null : _position.text.trim(),
        monthlySalary: salary,
        hireDate: _hireDate,
        terminationDate: _terminationDate,
        bornBefore1975: _bornBefore1975,
      );
    } else {
      await notifier.update(
        existing.copyWith(
          name: name,
          iin: _iin.text.trim().isEmpty ? null : _iin.text.trim(),
          position:
              _position.text.trim().isEmpty ? null : _position.text.trim(),
          monthlySalary: salary,
          hireDate: _hireDate,
          terminationDate: _terminationDate,
          bornBefore1975: _bornBefore1975,
          clearTermination: _terminationDate == null,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate({required bool isHire}) async {
    final initial =
        isHire ? _hireDate : (_terminationDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() {
        if (isHire) {
          _hireDate = picked;
        } else {
          _terminationDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: EsepColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: EsepColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.existing == null ? 'Новый сотрудник' : 'Редактировать',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Имя и фамилия',
                hintText: 'Например, Асель Жумабаева',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _position,
              decoration: const InputDecoration(
                labelText: 'Должность (необязательно)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _iin,
              decoration: const InputDecoration(
                labelText: 'ИИН (необязательно)',
                hintText: '12 цифр',
              ),
              keyboardType: TextInputType.number,
              maxLength: 12,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _salary,
              decoration: const InputDecoration(
                labelText: 'Ежемесячная зарплата, ₸',
                hintText: '250 000',
                suffixText: '₸',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _DateField(
              label: 'Дата приёма',
              date: _hireDate,
              onTap: () => _pickDate(isHire: true),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Дата увольнения',
              hint: 'Оставьте пустым, если работает',
              date: _terminationDate,
              onTap: () => _pickDate(isHire: false),
              onClear: _terminationDate == null
                  ? null
                  : () => setState(() => _terminationDate = null),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title:
                  const Text('Родился до 1975 года', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                'ОПВР работодателя не начисляется',
                style: TextStyle(fontSize: 11, color: EsepColors.textSecondary),
              ),
              value: _bornBefore1975,
              onChanged: (v) => setState(() => _bornBefore1975 = v),
              activeTrackColor: EsepColors.primary,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Iconsax.tick_circle),
                label: Text(widget.existing == null ? 'Добавить' : 'Сохранить'),
                style:
                    FilledButton.styleFrom(backgroundColor: EsepColors.primary),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.hint,
    this.onClear,
  });
  final String label;
  final String? hint;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(Iconsax.close_circle, size: 18),
                  onPressed: onClear,
                )
              : const Icon(Iconsax.calendar_1, size: 18),
        ),
        child: Text(
          date != null ? formatShortDate(date!) : (hint ?? ''),
          style: TextStyle(
            fontSize: 14,
            color: date != null
                ? EsepColors.textPrimary
                : EsepColors.textDisabled,
          ),
        ),
      ),
    );
  }
}
