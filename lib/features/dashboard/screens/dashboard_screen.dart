import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    // TODO: replace with real data from providers
    const income = 1250000.0;
    const expense = 380000.0;
    const profit = income - expense;
    const regimeLimit = 94500000.0; // упрощёнка полугодие
    final usedPercent = income / regimeLimit;

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
            Expanded(child: _MetricCard(label: 'Доход', amount: income, color: EsepColors.income, icon: Iconsax.arrow_circle_up)),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(label: 'Расход', amount: expense, color: EsepColors.expense, icon: Iconsax.arrow_circle_down)),
          ]),
          const SizedBox(height: 12),
          _MetricCard(label: 'Прибыль', amount: profit, color: EsepColors.primary, icon: Iconsax.wallet_3, large: true),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Лимит упрощёнки'),
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
                  '${fmt.format(income)} ₸ из ${fmt.format(regimeLimit)} ₸',
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Ближайшие события'),
          const SizedBox(height: 12),
          const _EventCard(
            icon: Iconsax.calendar_tick,
            title: 'Сдать 910 форму',
            subtitle: 'до 15 августа 2025',
            daysLeft: 45,
            color: EsepColors.warning,
          ),
          const SizedBox(height: 8),
          const _EventCard(
            icon: Iconsax.receipt_item,
            title: '3 неоплаченных счёта',
            subtitle: '450 000 ₸ к получению',
            daysLeft: null,
            color: EsepColors.info,
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Быстрые действия'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _QuickAction(icon: Iconsax.receipt_add, label: 'Новый счёт', onTap: () {})),
            const SizedBox(width: 12),
            Expanded(child: _QuickAction(icon: Iconsax.money_add, label: 'Доход', onTap: () {})),
            const SizedBox(width: 12),
            Expanded(child: _QuickAction(icon: Iconsax.money_remove, label: 'Расход', onTap: () {})),
            const SizedBox(width: 12),
            Expanded(child: _QuickAction(icon: Iconsax.calculator, label: 'Налоги', onTap: () {})),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _monthTitle() {
    final now = DateTime.now();
    return DateFormat('LLLL yyyy', 'ru_RU').format(now);
  }
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
