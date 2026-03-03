import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/accounting_client.dart';
import '../../../core/providers/accounting_provider.dart';

class AccountantClientDetailScreen extends ConsumerWidget {
  const AccountantClientDetailScreen({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(accountingProvider);
    final client  = clients.where((c) => c.id == clientId).firstOrNull;
    final fmt     = NumberFormat('#,##0', 'ru_RU');

    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Клиент')),
        body: const Center(child: Text('Клиент не найден')),
      );
    }

    final deadline   = nearestDeadline(client);
    final deadlines  = generateClientDeadlines(client, DateTime.now(), 90)
        .where((d) => !d.isPast)
        .take(5)
        .toList();
    final employeeCalcs = client.employees.map(calcEmployeeSocial).toList();
    final totalEmployerExtra =
        employeeCalcs.fold(0.0, (s, e) => s + e.employerExtra);
    final totalPayroll =
        employeeCalcs.fold(0.0, (s, e) => s + e.totalCost);

    return Scaffold(
      appBar: AppBar(
        title: Text(client.name, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Status banner ──────────────────────────────────────────────
          if (deadline != null)
            _StatusBanner(deadline: deadline),

          const SizedBox(height: 16),

          // ── Client info ────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Информация',
                    style: TextStyle(fontSize: 13, color: EsepColors.textSecondary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _DetailRow(
                    label: 'Тип',
                    value: '${client.entityType.label} · ${client.regime.label}'),
                _DetailRow(
                    label: client.entityType == ClientEntityType.ip ? 'ИИН' : 'БИН',
                    value: client.binOrIin),
                _DetailRow(
                    label: 'Сотрудников',
                    value: client.employees.isEmpty
                        ? 'Нет'
                        : '${client.employees.length} чел.'),
                if (client.monthlyFee > 0)
                  _DetailRow(
                    label: 'Гонорар',
                    value: '${fmt.format(client.monthlyFee)} ₸/мес',
                    valueColor: client.feeReceivedThisMonth
                        ? EsepColors.income
                        : EsepColors.expense,
                    trailing: GestureDetector(
                      onTap: () =>
                          ref.read(accountingProvider.notifier).toggleFee(client.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: client.feeReceivedThisMonth
                              ? EsepColors.income.withValues(alpha: 0.1)
                              : EsepColors.expense.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          client.feeReceivedThisMonth ? '✓ получен' : '× не получен',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: client.feeReceivedThisMonth
                                ? EsepColors.income
                                : EsepColors.expense,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (client.notes != null && client.notes!.isNotEmpty)
                  _DetailRow(label: 'Заметки', value: client.notes!),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // ── Document checklist ─────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(
                    child: Text('Чеклист документов',
                        style: TextStyle(fontSize: 13, color: EsepColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    '${client.checklist.where((d) => d.received).length}/'
                    '${client.checklist.length}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: EsepColors.primary),
                  ),
                ]),
                if (client.checklist.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Нет документов',
                        style: TextStyle(color: EsepColors.textSecondary, fontSize: 13)),
                  )
                else ...[
                  const SizedBox(height: 8),
                  ...client.checklist.map((doc) => InkWell(
                    onTap: () => ref
                        .read(accountingProvider.notifier)
                        .toggleDoc(client.id, doc.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(
                          doc.received
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: doc.received
                              ? EsepColors.income
                              : EsepColors.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(doc.label,
                              style: TextStyle(
                                fontSize: 13,
                                color: doc.received
                                    ? EsepColors.textSecondary
                                    : EsepColors.textPrimary,
                                decoration: doc.received
                                    ? TextDecoration.lineThrough
                                    : null,
                              )),
                        ),
                      ]),
                    ),
                  )),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // ── Employees + social calc ────────────────────────────────────
          if (client.employees.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(
                      child: Text('Сотрудники и начисления',
                          style: TextStyle(fontSize: 13, color: EsepColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ),
                    Text('${client.employees.length} чел.',
                        style: const TextStyle(
                            fontSize: 12, color: EsepColors.textSecondary)),
                  ]),
                  const SizedBox(height: 12),
                  ...employeeCalcs.map((calc) => _EmployeeCard(calc: calc, fmt: fmt)),
                  const Divider(height: 20),
                  Row(children: [
                    const Expanded(
                      child: Text('Итого расходы на ФОТ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${fmt.format(totalPayroll)} ₸',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: EsepColors.expense)),
                      Text('+${fmt.format(totalEmployerExtra)} ₸ налоги',
                          style: const TextStyle(
                              fontSize: 11, color: EsepColors.textSecondary)),
                    ]),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Upcoming deadlines ─────────────────────────────────────────
          if (deadlines.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Дедлайны (90 дней)',
                      style: TextStyle(fontSize: 13, color: EsepColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ...deadlines.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: d.isUrgent
                              ? EsepColors.expense
                              : d.isWarning
                                  ? EsepColors.warning
                                  : EsepColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.label,
                              style: const TextStyle(fontSize: 13,
                                  color: EsepColors.textPrimary)),
                          Text(
                            DateFormat('dd MMMM yyyy', 'ru_RU').format(d.date),
                            style: const TextStyle(fontSize: 11,
                                color: EsepColors.textSecondary),
                          ),
                        ]),
                      ),
                      _DaysTag(daysLeft: d.daysLeft),
                    ]),
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Status Banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.deadline});
  final ClientDeadline deadline;

  @override
  Widget build(BuildContext context) {
    final color = deadline.isUrgent
        ? EsepColors.expense
        : deadline.isWarning
            ? EsepColors.warning
            : EsepColors.primary;
    final icon = deadline.isUrgent ? Iconsax.danger : Iconsax.clock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(deadline.label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            Text(
              deadline.daysLeft == 0
                  ? 'Сегодня!'
                  : 'Через ${deadline.daysLeft} ${_daysWord(deadline.daysLeft)}',
              style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
            ),
          ]),
        ),
      ]),
    );
  }

  String _daysWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'дня';
    return 'дней';
  }
}

// ── Employee Card ─────────────────────────────────────────────────────────────

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.calc, required this.fmt});
  final EmployeeSocialCalc calc;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Iconsax.user, size: 14, color: EsepColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(calc.employee.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Text('${fmt.format(calc.employee.salary)} ₸',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: EsepColors.textPrimary)),
      ]),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          _TaxChip(label: 'ОПВ', amount: calc.opv, fmt: fmt,
              color: EsepColors.expense),
          _TaxChip(label: 'ИПН', amount: calc.ipn, fmt: fmt,
              color: EsepColors.expense),
          _TaxChip(label: 'ВОСМС(−)', amount: calc.vosmsSelf, fmt: fmt,
              color: EsepColors.expense),
          _TaxChip(label: 'На руки', amount: calc.netSalary, fmt: fmt,
              color: EsepColors.income),
          _TaxChip(label: 'ОПВР', amount: calc.opvr, fmt: fmt,
              color: const Color(0xFF7B2FBE)),
          _TaxChip(label: 'СО', amount: calc.so, fmt: fmt,
              color: const Color(0xFF7B2FBE)),
          _TaxChip(label: 'ВОСМС(+)', amount: calc.vosms, fmt: fmt,
              color: const Color(0xFF7B2FBE)),
        ]),
      ),
    ]),
  );
}

class _TaxChip extends StatelessWidget {
  const _TaxChip({
    required this.label,
    required this.amount,
    required this.fmt,
    required this.color,
  });
  final String label;
  final double amount;
  final NumberFormat fmt;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '$label: ${fmt.format(amount)} ₸',
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
    ),
  );
}

// ── Days Tag ──────────────────────────────────────────────────────────────────

class _DaysTag extends StatelessWidget {
  const _DaysTag({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final color = daysLeft <= 3
        ? EsepColors.expense
        : daysLeft <= 7
            ? EsepColors.warning
            : EsepColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        daysLeft == 0 ? 'сегодня' : '$daysLeft дн',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── Detail Row ────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });
  final String label, value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(
        width: 100,
        child: Text(label,
            style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
      ),
      Expanded(
        child: Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? EsepColors.textPrimary)),
      ),
      if (trailing != null) trailing!,
    ]),
  );
}
