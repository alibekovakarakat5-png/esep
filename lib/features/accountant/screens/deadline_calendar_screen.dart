import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/accounting_client.dart';
import '../../../core/providers/accounting_provider.dart';

class DeadlineCalendarScreen extends ConsumerWidget {
  const DeadlineCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadlines = ref.watch(allUpcomingDeadlinesProvider);

    // Group by date string
    final grouped = <String, List<ClientDeadline>>{};
    for (final d in deadlines) {
      if (d.isPast) continue;
      final key = DateFormat('yyyy-MM-dd').format(d.date);
      grouped.putIfAbsent(key, () => []).add(d);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Дедлайны'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${sortedKeys.length} дат',
                style: const TextStyle(
                    fontSize: 13, color: EsepColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
      body: deadlines.isEmpty
          ? const Center(
              child: Text('Нет предстоящих дедлайнов',
                  style: TextStyle(color: EsepColors.textSecondary)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedKeys.length,
              itemBuilder: (ctx, i) {
                final key   = sortedKeys[i];
                final date  = DateTime.parse(key);
                final items = grouped[key]!;
                final daysLeft = date.difference(DateTime.now()).inDays;

                final dateColor = daysLeft <= 3
                    ? EsepColors.expense
                    : daysLeft <= 7
                        ? EsepColors.warning
                        : EsepColors.primary;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date header
                    Padding(
                      padding: EdgeInsets.only(bottom: 8, top: i == 0 ? 0 : 16),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: dateColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('dd').format(date),
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700,
                                    color: dateColor, height: 1),
                              ),
                              Text(
                                DateFormat('MMM', 'ru_RU').format(date),
                                style: TextStyle(
                                    fontSize: 11, color: dateColor, height: 1.2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              _capitalize(DateFormat('EEEE', 'ru_RU').format(date)),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: EsepColors.textPrimary),
                            ),
                            Text(
                              daysLeft == 0
                                  ? 'Сегодня'
                                  : daysLeft == 1
                                      ? 'Завтра'
                                      : 'Через $daysLeft дн.',
                              style: TextStyle(fontSize: 12, color: dateColor),
                            ),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: dateColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${items.length} событ.',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: dateColor),
                          ),
                        ),
                      ]),
                    ),

                    // Deadline items
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: items.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final d   = entry.value;
                          return Column(children: [
                            _DeadlineRow(deadline: d),
                            if (idx < items.length - 1)
                              const Divider(height: 1, indent: 56),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Deadline Row ──────────────────────────────────────────────────────────────

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.deadline});
  final ClientDeadline deadline;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(deadline.type);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_typeIcon(deadline.type), color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(deadline.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                    color: EsepColors.textPrimary)),
            Text(deadline.clientName,
                style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
          ]),
        ),
        _TypeBadge(type: deadline.type, color: color),
      ]),
    );
  }

  static Color _typeColor(String type) => switch (type) {
        '910'     => EsepColors.primary,
        'social'  => EsepColors.warning,
        'payroll' => const Color(0xFF7B2FBE),
        '200'     => EsepColors.info,
        '700'     => EsepColors.expense,
        'esp'     => EsepColors.income,
        _         => EsepColors.textSecondary,
      };

  static IconData _typeIcon(String type) => switch (type) {
        '910'     => Iconsax.document_text,
        'social'  => Iconsax.money_send,
        'payroll' => Iconsax.people,
        '200'     => Iconsax.document_text,
        '700'     => Iconsax.document_text,
        'esp'     => Iconsax.receipt,
        _         => Iconsax.calendar_1,
      };
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type, required this.color});
  final String type;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      _typeLabel(type),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );

  static String _typeLabel(String type) => switch (type) {
        '910'     => '910',
        'social'  => 'Соцплатежи',
        'payroll' => 'ФОТ',
        '200'     => '200.00',
        '700'     => '700.00',
        'esp'     => 'ЕСП',
        _         => type,
      };
}
