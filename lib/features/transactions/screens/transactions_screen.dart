import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
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

  static const _mockIncome = [
    _TxMock('Оплата за разработку', 'Ромашка ТОО', 150000, '01.06', 'kaspi'),
    _TxMock('Консультация', 'ИП Сейткали', 25000, '03.06', 'наличные'),
    _TxMock('Поддержка сайта', 'Алтын Групп', 80000, '05.06', 'kaspi'),
  ];

  static const _mockExpense = [
    _TxMock('Аренда офиса', 'ТОО Аренда+', 85000, '01.06', 'перевод'),
    _TxMock('Реклама Instagram', 'Meta Ads', 30000, '02.06', 'карта'),
    _TxMock('Интернет', 'Beeline KZ', 8500, '01.06', 'карта'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Учёт'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: EsepColors.primary,
          unselectedLabelColor: EsepColors.textSecondary,
          indicatorColor: EsepColors.primary,
          tabs: const [Tab(text: 'Доходы'), Tab(text: 'Расходы')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: EsepColors.primary,
        child: const Icon(Iconsax.add, color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TxList(items: _mockIncome, isIncome: true),
          _TxList(items: _mockExpense, isIncome: false),
        ],
      ),
    );
  }
}

class _TxMock {
  const _TxMock(this.title, this.party, this.amount, this.date, this.source);
  final String title, party, date, source;
  final double amount;
}

class _TxList extends StatelessWidget {
  const _TxList({required this.items, required this.isIncome});
  final List<_TxMock> items;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final total = items.fold(0.0, (sum, t) => sum + t.amount);
    final color = isIncome ? EsepColors.income : EsepColors.expense;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: color.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(isIncome ? Iconsax.arrow_circle_up : Iconsax.arrow_circle_down, color: color),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isIncome ? 'Итого доходов' : 'Итого расходов', style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                Text('${fmt.format(total)} ₸', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        ...items.map((tx) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TxTile(tx: tx, isIncome: isIncome, fmt: fmt),
            )),
      ],
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, required this.isIncome, required this.fmt});
  final _TxMock tx;
  final bool isIncome;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? EsepColors.income : EsepColors.expense;
    return Card(
      child: ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(isIncome ? Iconsax.arrow_up_2 : Iconsax.arrow_down_2, color: color, size: 22),
        ),
        title: Text(tx.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('${tx.party} · ${tx.source}', style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isIncome ? '+' : '−'} ${fmt.format(tx.amount)} ₸',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
            ),
            Text(tx.date, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
