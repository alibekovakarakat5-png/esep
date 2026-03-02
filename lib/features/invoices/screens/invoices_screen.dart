import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';

enum InvoiceStatus { draft, sent, paid, overdue }

extension InvoiceStatusExt on InvoiceStatus {
  String get label => switch (this) {
        InvoiceStatus.draft => 'Черновик',
        InvoiceStatus.sent => 'Отправлен',
        InvoiceStatus.paid => 'Оплачен',
        InvoiceStatus.overdue => 'Просрочен',
      };
  Color get color => switch (this) {
        InvoiceStatus.draft => EsepColors.textSecondary,
        InvoiceStatus.sent => EsepColors.info,
        InvoiceStatus.paid => EsepColors.income,
        InvoiceStatus.overdue => EsepColors.expense,
      };
}

class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  static final _mock = [
    const _InvoiceMock('СЧ-2025-003', 'Ромашка ТОО', 150000, InvoiceStatus.sent),
    const _InvoiceMock('СЧ-2025-002', 'ИП Сейткали', 75000, InvoiceStatus.paid),
    const _InvoiceMock('СЧ-2025-001', 'Алтын Групп', 320000, InvoiceStatus.overdue),
  ];

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Счета'),
        actions: [
          IconButton(icon: const Icon(Iconsax.filter), onPressed: () {}),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: EsepColors.primary,
        icon: const Icon(Iconsax.add, color: Colors.white),
        label: const Text('Новый счёт', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            _SummaryChip(label: 'Ожидает', amount: 225000, color: EsepColors.info),
            const SizedBox(width: 8),
            _SummaryChip(label: 'Просрочено', amount: 320000, color: EsepColors.expense),
            const SizedBox(width: 8),
            _SummaryChip(label: 'Оплачено', amount: 75000, color: EsepColors.income),
          ]),
          const SizedBox(height: 20),
          ..._mock.map((inv) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InvoiceTile(invoice: inv, fmt: fmt),
              )),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.amount, required this.color});
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text('${fmt.format(amount)} ₸', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}

class _InvoiceMock {
  const _InvoiceMock(this.number, this.client, this.amount, this.status);
  final String number, client;
  final double amount;
  final InvoiceStatus status;
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.fmt});
  final _InvoiceMock invoice;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: EsepColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Iconsax.receipt_2, color: EsepColors.primary, size: 22),
          ),
          title: Text(invoice.client, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(invoice.number, style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${fmt.format(invoice.amount)} ₸', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: invoice.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(invoice.status.label, style: TextStyle(fontSize: 11, color: invoice.status.color, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
}
