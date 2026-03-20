import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/invoice.dart';
import '../../../core/providers/invoice_provider.dart';
import '../../../core/providers/client_provider.dart';
import '../../../core/providers/subscription_provider.dart';
import '../../../core/services/excel_export_service.dart';
import '../../../shared/widgets/adaptive_sheet.dart';

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

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  InvoiceStatus? _filter; // null = все

  @override
  Widget build(BuildContext context) {
    final allInvoices = ref.watch(invoiceProvider);
    final fmt = NumberFormat('#,##0', 'ru_RU');

    final invoices = _filter == null
        ? allInvoices
        : allInvoices.where((i) => i.status == _filter).toList();

    final pending = allInvoices.where((i) => i.status == InvoiceStatus.sent).fold(0.0, (s, i) => s + i.totalAmount);
    final overdue = allInvoices.where((i) => i.status == InvoiceStatus.overdue).fold(0.0, (s, i) => s + i.totalAmount);
    final paid = allInvoices.where((i) => i.status == InvoiceStatus.paid).fold(0.0, (s, i) => s + i.totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Счета'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.document_download),
            tooltip: 'Экспорт в Excel',
            onPressed: () {
              final all = ref.read(invoiceProvider);
              if (all.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Нет счетов для экспорта')),
                );
                return;
              }
              ExcelExportService.exportInvoices(all);
            },
          ),
          IconButton(
            icon: Icon(Iconsax.filter,
                color: _filter != null ? EsepColors.primary : null),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateInvoice(context),
        backgroundColor: EsepColors.primary,
        icon: const Icon(Iconsax.add, color: Colors.white),
        label: const Text('Новый счёт', style: TextStyle(color: Colors.white)),
      ),
      body: invoices.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Iconsax.receipt_2, color: EsepColors.textDisabled, size: 48),
                SizedBox(height: 12),
                Text('Нет счетов', style: TextStyle(color: EsepColors.textSecondary, fontSize: 16)),
                SizedBox(height: 4),
                Text('Создайте первый счёт для клиента',
                    style: TextStyle(color: EsepColors.textDisabled, fontSize: 13)),
              ]),
            )
          : _buildBody(context, invoices, pending, overdue, paid, fmt),
    );
  }

  Widget _buildBody(BuildContext context, List<Invoice> invoices, double pending, double overdue, double paid, NumberFormat fmt) {
    final wide = isDesktop(context);
    final dateFmt = DateFormat('dd.MM.yyyy', 'ru_RU');

    final summaryRow = Row(children: [
      _SummaryChip(label: 'Ожидает', amount: pending, color: EsepColors.info),
      const SizedBox(width: 8),
      _SummaryChip(label: 'Просрочено', amount: overdue, color: EsepColors.expense),
      const SizedBox(width: 8),
      _SummaryChip(label: 'Оплачено', amount: paid, color: EsepColors.income),
    ]);

    if (wide) {
      // Desktop: inline filter chips + DataTable
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          summaryRow,
          const SizedBox(height: 16),
          // Inline filter chips
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Все'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
                selectedColor: EsepColors.primary.withValues(alpha: 0.15),
              ),
              ...InvoiceStatus.values.map((s) => FilterChip(
                label: Text(s.label),
                selected: _filter == s,
                onSelected: (_) => setState(() => _filter = s),
                selectedColor: s.color.withValues(alpha: 0.15),
                avatar: Icon(Icons.circle, color: s.color, size: 10),
              )),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: DataTable(
              columnSpacing: 24,
              headingRowColor: WidgetStateProperty.all(
                EsepColors.primary.withValues(alpha: 0.05),
              ),
              columns: const [
                DataColumn(label: Text('№', style: TextStyle(fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Клиент', style: TextStyle(fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Дата', style: TextStyle(fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Сумма', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                DataColumn(label: Text('Статус', style: TextStyle(fontWeight: FontWeight.w600))),
              ],
              rows: invoices.map((inv) => DataRow(
                cells: [
                  DataCell(
                    Text(inv.number, style: const TextStyle(fontSize: 13)),
                    onTap: () => context.go('/invoices/${inv.id}'),
                  ),
                  DataCell(
                    Text(inv.clientName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    onTap: () => context.go('/invoices/${inv.id}'),
                  ),
                  DataCell(Text(dateFmt.format(inv.createdAt), style: const TextStyle(fontSize: 13))),
                  DataCell(Text('${fmt.format(inv.totalAmount)} ₸',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  DataCell(
                    PopupMenuButton<InvoiceStatus>(
                      initialValue: inv.status,
                      onSelected: (s) => ref.read(invoiceProvider.notifier).updateStatus(inv.id, s),
                      itemBuilder: (_) => InvoiceStatus.values.map((s) => PopupMenuItem(
                        value: s,
                        child: Row(children: [
                          Icon(Icons.circle, color: s.color, size: 10),
                          const SizedBox(width: 8),
                          Text(s.label),
                        ]),
                      )).toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: inv.status.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(inv.status.label,
                              style: TextStyle(fontSize: 12, color: inv.status.color, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, size: 16, color: inv.status.color),
                        ]),
                      ),
                    ),
                  ),
                ],
              )).toList(),
            ),
          ),
        ],
      );
    }

    // Mobile: card list
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        summaryRow,
        const SizedBox(height: 20),
        ...invoices.map((inv) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Dismissible(
                key: Key(inv.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: EsepColors.expense.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Iconsax.trash, color: EsepColors.expense),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Удалить счёт?'),
                      content: Text('Счёт ${inv.number} для ${inv.clientName} будет удалён.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Удалить', style: TextStyle(color: EsepColors.expense)),
                        ),
                      ],
                    ),
                  ) ?? false;
                },
                onDismissed: (_) => ref.read(invoiceProvider.notifier).remove(inv.id),
                child: GestureDetector(
                  onTap: () => context.go('/invoices/${inv.id}'),
                  child: _InvoiceTile(invoice: inv, fmt: fmt, onStatusChange: (status) {
                    ref.read(invoiceProvider.notifier).updateStatus(inv.id, status);
                  }),
                ),
              ),
            )),
      ],
    );
  }

  void _showFilterSheet(BuildContext context) {
    showAdaptiveSheet(
      context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Фильтр по статусу',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          ListTile(
            leading: Icon(Icons.circle,
                color: _filter == null ? EsepColors.primary : EsepColors.textSecondary,
                size: 12),
            title: const Text('Все счета'),
            trailing: _filter == null ? const Icon(Icons.check, color: EsepColors.primary) : null,
            onTap: () { setState(() => _filter = null); Navigator.pop(ctx); },
          ),
          ...InvoiceStatus.values.map((s) => ListTile(
            leading: Icon(Icons.circle, color: s.color, size: 12),
            title: Text(s.label),
            trailing: _filter == s ? const Icon(Icons.check, color: EsepColors.primary) : null,
            onTap: () { setState(() => _filter = s); Navigator.pop(ctx); },
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showCreateInvoice(BuildContext context) {
    final sub = ref.read(subscriptionProvider);
    final allInvoices = ref.read(invoiceProvider);
    if (!canAddInvoice(sub, allInvoices.length)) {
      showPaywall(context, feature: 'Создание счетов');
      return;
    }
    final clients = ref.read(clientProvider);
    final clientNameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showAdaptiveSheet(
      context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Новый счёт', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          if (clients.isNotEmpty)
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Клиент', prefixIcon: Icon(Iconsax.user)),
              items: clients.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
              onChanged: (v) => clientNameCtrl.text = v ?? '',
            )
          else
            TextField(
              controller: clientNameCtrl,
              decoration: const InputDecoration(labelText: 'Клиент', prefixIcon: Icon(Iconsax.user)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: descCtrl,
            decoration: const InputDecoration(labelText: 'Описание услуги', prefixIcon: Icon(Iconsax.document_text)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            decoration: const InputDecoration(labelText: 'Сумма', prefixIcon: Icon(Iconsax.money_3), suffixText: '₸'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.replaceAll(' ', ''));
              if (clientNameCtrl.text.isEmpty || descCtrl.text.isEmpty || amount == null) return;
              ref.read(invoiceProvider.notifier).add(
                    clientId: '',
                    clientName: clientNameCtrl.text.trim(),
                    items: [InvoiceItem(id: '', description: descCtrl.text.trim(), quantity: 1, unitPrice: amount)],
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Создать счёт'),
          ),
        ]),
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text('${fmt.format(amount)} ₸', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.fmt, required this.onStatusChange});
  final Invoice invoice;
  final NumberFormat fmt;
  final void Function(InvoiceStatus) onStatusChange;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: EsepColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Iconsax.receipt_2, color: EsepColors.primary, size: 22),
          ),
          title: Text(invoice.clientName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(invoice.number, style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${fmt.format(invoice.totalAmount)} ₸', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _showStatusMenu(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: invoice.status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(invoice.status.label,
                      style: TextStyle(fontSize: 11, color: invoice.status.color, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ),
      );

  void _showStatusMenu(BuildContext context) {
    showAdaptiveSheet(
      context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Изменить статус', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ...InvoiceStatus.values.map((s) => ListTile(
                leading: Icon(Icons.circle, color: s.color, size: 12),
                title: Text(s.label),
                onTap: () {
                  onStatusChange(s);
                  Navigator.pop(ctx);
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
