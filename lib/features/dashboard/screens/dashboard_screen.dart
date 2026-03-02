import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/providers/invoice_provider.dart';
import '../../transactions/screens/add_transaction_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,##0', 'ru_RU');

    final monthIncome = ref.watch(monthIncomeProvider);
    final monthExpense = ref.watch(monthExpenseProvider);
    final profit = monthIncome - monthExpense;
    final halfYearIncome = ref.watch(halfYearIncomeProvider);
    final regimeLimit = KzTax.simplified910HalfYearLimit;
    final usedPercent = regimeLimit > 0 ? halfYearIncome / regimeLimit : 0.0;
    final social = KzTax.calculateMonthlySocial();
    final unpaidCount = ref.watch(unpaidInvoicesProvider).length;
    final unpaidTotal = ref.watch(totalUnpaidProvider);
    final nextDeadline = _nextDeadline();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Есеп'),
        actions: [
          IconButton(icon: const Icon(Iconsax.notification), onPressed: () {}),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: _monthTitle()),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _MetricCard(label: 'Доход', amount: monthIncome, color: EsepColors.income, icon: Iconsax.arrow_circle_up)),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(label: 'Расход', amount: monthExpense, color: EsepColors.expense, icon: Iconsax.arrow_circle_down)),
          ]),
          const SizedBox(height: 12),
          _MetricCard(label: 'Прибыль', amount: profit, color: profit >= 0 ? EsepColors.primary : EsepColors.expense, icon: Iconsax.wallet_3, large: true),

          const SizedBox(height: 24),
          _SectionHeader(title: 'Лимит упрощёнки (полугодие)'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Использовано', style: TextStyle(color: EsepColors.textSecondary, fontSize: 13)),
                  const Spacer(),
                  Text('${(usedPercent * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontWeight: FontWeight.w600, color: usedPercent > 0.8 ? EsepColors.expense : EsepColors.textPrimary)),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: usedPercent.clamp(0.0, 1.0),
                  backgroundColor: EsepColors.divider,
                  valueColor: AlwaysStoppedAnimation(usedPercent > 0.8 ? EsepColors.expense : EsepColors.primary),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  '${fmt.format(halfYearIncome)} ₸ из ${fmt.format(regimeLimit)} ₸',
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                ),
              ]),
            ),
          ),

          // Social payments
          const SizedBox(height: 24),
          _SectionHeader(title: 'Соцплатежи "за себя"'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: EsepColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Iconsax.calendar_1, color: EsepColors.warning, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${fmt.format(social.total)} ₸/мес',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: EsepColors.warning)),
                  const Text('ОПВ + ОПВР + СО + ВОСМС · до 25 числа',
                      style: TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
                ])),
              ]),
            ),
          ),

          const SizedBox(height: 24),
          _SectionHeader(title: 'Ближайшие события'),
          const SizedBox(height: 12),
          _EventCard(
            icon: Iconsax.calendar_tick,
            title: 'Сдать 910 форму',
            subtitle: 'до ${nextDeadline.label}',
            daysLeft: nextDeadline.daysLeft,
            color: nextDeadline.daysLeft < 30 ? EsepColors.expense : EsepColors.warning,
          ),
          const SizedBox(height: 8),
          _EventCard(
            icon: Iconsax.money_send,
            title: 'Соцплатежи за ${_prevMonthName()}',
            subtitle: '${fmt.format(social.total)} ₸ до 25 числа',
            daysLeft: _daysUntilSocialPayment(),
            color: EsepColors.warning,
          ),
          if (unpaidCount > 0) ...[
            const SizedBox(height: 8),
            _EventCard(
              icon: Iconsax.receipt_item,
              title: '$unpaidCount неоплаченных счетов',
              subtitle: '${fmt.format(unpaidTotal)} ₸ к получению',
              daysLeft: null,
              color: EsepColors.info,
            ),
          ],

          const SizedBox(height: 24),
          _SectionHeader(title: 'Быстрые действия'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _QuickAction(icon: Iconsax.receipt_add, label: 'Новый счёт', onTap: () => context.go('/invoices'))),
            const SizedBox(width: 12),
            Expanded(child: _QuickAction(icon: Iconsax.money_add, label: 'Доход', onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddTransactionScreen(isIncome: true)));
            })),
            const SizedBox(width: 12),
            Expanded(child: _QuickAction(icon: Iconsax.money_remove, label: 'Расход', onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddTransactionScreen(isIncome: false)));
            })),
            const SizedBox(width: 12),
            Expanded(child: _QuickAction(icon: Iconsax.calculator, label: 'Налоги', onTap: () => context.go('/taxes'))),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _monthTitle() {
    final now = DateTime.now();
    return DateFormat('LLLL yyyy', 'ru_RU').format(now);
  }

  static _DeadlineInfo _nextDeadline() {
    final now = DateTime.now();
    DateTime next;
    String label;
    if (now.month < 8 || (now.month == 8 && now.day <= 15)) {
      next = DateTime(now.year, 8, 15);
      label = '15 августа ${now.year}';
    } else {
      final year = now.month > 8 ? now.year + 1 : now.year;
      next = DateTime(year, 2, 15);
      label = '15 февраля $year';
    }
    return _DeadlineInfo(label: label, daysLeft: next.difference(now).inDays);
  }

  static String _prevMonthName() {
    final prev = DateTime.now().subtract(const Duration(days: 15));
    return DateFormat('MMMM', 'ru_RU').format(prev);
  }

  static int _daysUntilSocialPayment() {
    final now = DateTime.now();
    var deadline = DateTime(now.year, now.month, 25);
    if (now.day > 25) {
      deadline = DateTime(now.year, now.month + 1, 25);
    }
    return deadline.difference(now).inDays;
  }
}

class _DeadlineInfo {
  final String label;
  final int daysLeft;
  const _DeadlineInfo({required this.label, required this.daysLeft});
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: EsepColors.textPrimary),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.amount, required this.color, required this.icon, this.large = false});
  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    return Card(
      child: Padding(
        padding: EdgeInsets.all(large ? 20 : 16),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
            Text('${fmt.format(amount)} ₸', style: TextStyle(fontSize: large ? 18 : 15, fontWeight: FontWeight.w600, color: color)),
          ]),
        ]),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.icon, required this.title, required this.subtitle, required this.daysLeft, required this.color});
  final IconData icon;
  final String title, subtitle;
  final int? daysLeft;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          trailing: daysLeft != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('$daysLeft дн', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                )
              : null,
        ),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Icon(icon, color: EsepColors.primary, size: 24),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary), textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}
