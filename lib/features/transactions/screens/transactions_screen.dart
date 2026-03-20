import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/transaction.dart' as model;
import '../../../core/providers/transaction_provider.dart';
import '../../../core/providers/subscription_provider.dart';
import '../../../core/services/excel_export_service.dart';
import 'add_transaction_screen.dart';
import 'kaspi_import_screen.dart';
import 'receipt_scanner_stub.dart'
    if (dart.library.io) 'receipt_scanner_screen.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incomes = ref.watch(incomeTransactionsProvider);
    final expenses = ref.watch(expenseTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Учёт'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.document_download),
            tooltip: 'Экспорт в Excel',
            onPressed: () {
              final all = ref.read(transactionProvider);
              if (all.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Нет транзакций для экспорта')),
                );
                return;
              }
              ExcelExportService.exportTransactions(all);
            },
          ),
          IconButton(
            icon: const Icon(Iconsax.scan),
            tooltip: 'Сканер чеков',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReceiptScannerScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Iconsax.import),
            tooltip: 'Импорт Kaspi',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KaspiImportScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: EsepColors.primary,
          unselectedLabelColor: EsepColors.textSecondary,
          indicatorColor: EsepColors.primary,
          tabs: [
            Tab(text: 'Доходы (${incomes.length})'),
            Tab(text: 'Расходы (${expenses.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTransaction(context),
        backgroundColor: EsepColors.primary,
        child: const Icon(Iconsax.add, color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TxList(items: incomes, isIncome: true, onDelete: _delete, onEdit: _edit),
          _TxList(items: expenses, isIncome: false, onDelete: _delete, onEdit: _edit),
        ],
      ),
    );
  }

  void _addTransaction(BuildContext context) {
    final sub = ref.read(subscriptionProvider);
    final monthCount = ref.read(monthTransactionCountProvider);
    if (!canAddTransaction(sub, monthCount)) {
      showPaywall(context, feature: 'Добавление операций');
      return;
    }
    final isIncome = _tabs.index == 0;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddTransactionScreen(isIncome: isIncome),
    ));
  }

  void _delete(String id) {
    ref.read(transactionProvider.notifier).remove(id);
  }

  void _edit(model.Transaction tx) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddTransactionScreen(isIncome: tx.isIncome, existing: tx),
    ));
  }
}

class _TxList extends StatelessWidget {
  const _TxList({required this.items, required this.isIncome, required this.onDelete, required this.onEdit});
  final List<model.Transaction> items;
  final bool isIncome;
  final void Function(String) onDelete;
  final void Function(model.Transaction) onEdit;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final total = items.fold(0.0, (sum, t) => sum + t.amount);
    final color = isIncome ? EsepColors.income : EsepColors.expense;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(isIncome ? Iconsax.arrow_circle_up : Iconsax.arrow_circle_down,
              color: EsepColors.textDisabled, size: 48),
          const SizedBox(height: 12),
          Text(
            isIncome ? 'Нет доходов' : 'Нет расходов',
            style: const TextStyle(color: EsepColors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text('Нажмите + чтобы добавить',
              style: TextStyle(color: EsepColors.textDisabled, fontSize: 13)),
        ]),
      );
    }

    final summaryCard = Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(isIncome ? Iconsax.arrow_circle_up : Iconsax.arrow_circle_down, color: color),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isIncome ? 'Итого доходов' : 'Итого расходов',
                style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
            Text('${fmt.format(total)} ₸',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          ]),
          const Spacer(),
          Text('${items.length} операций',
              style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
        ]),
      ),
    );

    if (wide) {
      final dateFmt = DateFormat('dd.MM.yyyy', 'ru_RU');
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          summaryCard,
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: DataTable(
              columnSpacing: 24,
              headingRowColor: WidgetStateProperty.all(
                color.withValues(alpha: 0.05),
              ),
              columns: const [
                DataColumn(label: Text('Дата', style: TextStyle(fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Описание', style: TextStyle(fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Клиент', style: TextStyle(fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Источник', style: TextStyle(fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Сумма', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.w600))),
              ],
              rows: items.map((tx) => DataRow(
                cells: [
                  DataCell(Text(dateFmt.format(tx.date), style: const TextStyle(fontSize: 13))),
                  DataCell(Text(tx.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  DataCell(Text(tx.clientName ?? '', style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary))),
                  DataCell(Text(tx.source ?? '', style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary))),
                  DataCell(Text(
                    '${isIncome ? '+' : '−'} ${fmt.format(tx.amount)} ₸',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                  )),
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Iconsax.edit_2, size: 18),
                      tooltip: 'Редактировать',
                      onPressed: () => onEdit(tx),
                    ),
                    IconButton(
                      icon: const Icon(Iconsax.trash, size: 18, color: EsepColors.expense),
                      tooltip: 'Удалить',
                      onPressed: () => _confirmDelete(context, tx),
                    ),
                  ])),
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
        summaryCard,
        const SizedBox(height: 16),
        ...items.map((tx) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TxTile(tx: tx, isIncome: isIncome, fmt: fmt, onDelete: onDelete, onEdit: onEdit),
            )),
      ],
    );
  }

  void _confirmDelete(BuildContext context, model.Transaction tx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: EsepColors.expense)),
          ),
        ],
      ),
    ) ?? false;
    if (ok) onDelete(tx.id);
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, required this.isIncome, required this.fmt, required this.onDelete, required this.onEdit});
  final model.Transaction tx;
  final bool isIncome;
  final NumberFormat fmt;
  final void Function(String) onDelete;
  final void Function(model.Transaction) onEdit;

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? EsepColors.income : EsepColors.expense;
    final dateFmt = DateFormat('dd.MM', 'ru_RU');
    return Dismissible(
      key: Key(tx.id),
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
            title: const Text('Удалить?'),
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
      onDismissed: (_) => onDelete(tx.id),
      child: Card(
        child: ListTile(
          onTap: () => onEdit(tx),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(isIncome ? Iconsax.arrow_up_2 : Iconsax.arrow_down_2, color: color, size: 22),
          ),
          title: Text(tx.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            [tx.clientName, tx.source].where((s) => s != null && s.isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : '−'} ${fmt.format(tx.amount)} ₸',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
              ),
              Text(dateFmt.format(tx.date),
                  style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
