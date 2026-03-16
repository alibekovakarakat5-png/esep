import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/providers/invoice_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,##0', 'ru_RU');

    final monthIncome    = ref.watch(monthIncomeProvider);
    final monthExpense   = ref.watch(monthExpenseProvider);
    final profit         = monthIncome - monthExpense;
    final monthlyData    = ref.watch(monthlyChartProvider);
    final halfYearIncome = ref.watch(halfYearIncomeProvider);
    final regimeLimit    = KzTax.simplified910HalfYearLimit;
    final usedPercent    = regimeLimit > 0 ? halfYearIncome / regimeLimit : 0.0;
    final social         = KzTax.calculateMonthlySocial();
    final unpaidCount    = ref.watch(unpaidInvoicesProvider).length;
    final unpaidTotal    = ref.watch(totalUnpaidProvider);
    final transactions   = ref.watch(transactionProvider);
    final recentTxs      = transactions.take(5).toList();
    final isLoading      = ref.watch(transactionLoadingProvider) || ref.watch(invoiceLoadingProvider);
    final socialDays     = _daysUntilSocialPayment();
    final deadlineInfo   = _nextDeadline();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Есеп'),
        actions: [
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              icon: const Icon(Iconsax.setting_2),
              tooltip: 'Настройки',
              onPressed: () => context.go('/settings'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // 1. Быстрые действия — первое что видит пользователь
          Row(children: [
            Expanded(child: _ActionButton(
              icon: Iconsax.arrow_circle_up,
              label: '+ Доход',
              color: EsepColors.income,
              onTap: () => _showQuickAdd(context, ref, isIncome: true),
            )),
            const SizedBox(width: 10),
            Expanded(child: _ActionButton(
              icon: Iconsax.arrow_circle_down,
              label: '+ Расход',
              color: EsepColors.expense,
              onTap: () => _showQuickAdd(context, ref, isIncome: false),
            )),
            const SizedBox(width: 10),
            Expanded(child: _ActionButton(
              icon: Iconsax.receipt_add,
              label: 'Счёт',
              color: EsepColors.primary,
              onTap: () => context.go('/invoices'),
            )),
          ]),

          // 2. Дедлайн-баннер (если скоро платёж)
          if (socialDays <= 7) ...[
            const SizedBox(height: 12),
            _DeadlineBanner(
              message: socialDays == 0
                  ? 'Соцплатежи сегодня! — ${fmt.format(social.total)} ₸'
                  : 'Соцплатежи через $socialDays ${_daysWord(socialDays)} — ${fmt.format(social.total)} ₸ до 25-го',
              urgent: socialDays <= 3,
            ),
          ] else if (deadlineInfo.daysLeft <= 30) ...[
            const SizedBox(height: 12),
            _DeadlineBanner(
              message: '910 форма через ${deadlineInfo.daysLeft} дн — до ${deadlineInfo.label}',
              urgent: deadlineInfo.daysLeft <= 7,
            ),
          ],

          // 3. Метрики месяца
          const SizedBox(height: 16),
          _MetricsSummary(
            title: _monthTitle(),
            income: monthIncome,
            expense: monthExpense,
            profit: profit,
          ),

          // 4. Налоговый прогноз — сколько отложить
          if (halfYearIncome > 0) ...[
            const SizedBox(height: 12),
            _TaxForecastCard(
              halfYearIncome: halfYearIncome,
              monthIncome: monthIncome,
              socialMonthly: social.total,
            ),
          ],

          // Последние операции
          if (recentTxs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(
                child: Text('Последние операции',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: EsepColors.textPrimary)),
              ),
              TextButton(
                onPressed: () => context.go('/transactions'),
                child: const Text('Все', style: TextStyle(fontSize: 13, color: EsepColors.primary)),
              ),
            ]),
            const SizedBox(height: 4),
            Card(
              child: Column(
                children: recentTxs.asMap().entries.map((e) {
                  final i   = e.key;
                  final tx  = e.value;
                  final color = tx.isIncome ? EsepColors.income : EsepColors.expense;
                  return Column(children: [
                    ListTile(
                      dense: true,
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(tx.isIncome ? Iconsax.arrow_circle_up : Iconsax.arrow_circle_down, color: color, size: 18),
                      ),
                      title: Text(tx.title,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(DateFormat('dd MMM', 'ru_RU').format(tx.date),
                          style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
                      trailing: Text(
                        '${tx.isIncome ? "+" : "−"} ${fmt.format(tx.amount)} ₸',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
                    if (i < recentTxs.length - 1)
                      const Divider(height: 1, indent: 56, endIndent: 16),
                  ]);
                }).toList(),
              ),
            ),
          ],

          // 5. Неоплаченные счета
          if (unpaidCount > 0) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.go('/invoices'),
              child: _EventCard(
                icon: Iconsax.receipt_item,
                title: '$unpaidCount ${_invoiceWord(unpaidCount)} на ${fmt.format(unpaidTotal)} ₸',
                subtitle: 'Нажмите чтобы перейти к счетам',
                daysLeft: null,
                color: EsepColors.info,
              ),
            ),
          ],

          // 6. График
          const SizedBox(height: 20),
          const Text('Доходы и расходы за 6 месяцев',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: EsepColors.textPrimary)),
          const SizedBox(height: 8),
          _MonthlyChart(data: monthlyData),

          // 7. Лимит упрощёнки
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Лимит упрощёнки (полугодие)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: EsepColors.textPrimary)),
                  const Spacer(),
                  Text('${(usedPercent * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: usedPercent > 0.8 ? EsepColors.expense : EsepColors.textPrimary)),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: usedPercent.clamp(0.0, 1.0),
                  backgroundColor: EsepColors.divider,
                  valueColor: AlwaysStoppedAnimation(usedPercent > 0.8 ? EsepColors.expense : EsepColors.primary),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                Text('${fmt.format(halfYearIncome)} ₸ из ${fmt.format(regimeLimit)} ₸',
                    style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
              ]),
            ),
          ),

          // 8. Соцплатежи
          const SizedBox(height: 12),
          _EventCard(
            icon: Iconsax.money_send,
            title: '${fmt.format(social.total)} ₸ — соцплатежи',
            subtitle: 'ОПВ + ОПВР + СО + ВОСМС · до 25 числа',
            daysLeft: socialDays,
            color: socialDays <= 7 ? EsepColors.expense : EsepColors.warning,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static void _showQuickAdd(BuildContext context, WidgetRef ref, {required bool isIncome}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _QuickAddSheet(isIncome: isIncome, ref: ref),
    );
  }

  static String _monthTitle() {
    final now = DateTime.now();
    final s = DateFormat('LLLL yyyy', 'ru_RU').format(now);
    return s[0].toUpperCase() + s.substring(1);
  }

  static _DeadlineInfo _nextDeadline() {
    final now = DateTime.now();
    DateTime next;
    String label;
    if (now.month < 8 || (now.month == 8 && now.day <= 15)) {
      next  = DateTime(now.year, 8, 15);
      label = '15 авг ${now.year}';
    } else {
      final year = now.month > 8 ? now.year + 1 : now.year;
      next  = DateTime(year, 2, 15);
      label = '15 фев $year';
    }
    return _DeadlineInfo(label: label, daysLeft: next.difference(now).inDays);
  }

  static int _daysUntilSocialPayment() {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, 25);
    if (now.day > 25) d = DateTime(now.year, now.month + 1, 25);
    return d.difference(now).inDays;
  }

  static String _daysWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'дня';
    return 'дней';
  }

  static String _invoiceWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'неоплаченный счёт';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'неоплаченных счёта';
    return 'неоплаченных счетов';
  }
}

class _DeadlineInfo {
  final String label;
  final int daysLeft;
  const _DeadlineInfo({required this.label, required this.daysLeft});
}

// ── Quick Add Bottom Sheet ─────────────────────────────────────────────────────
class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({required this.isIncome, required this.ref});
  final bool isIncome;
  final WidgetRef ref;

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _amountCtrl = TextEditingController();
  final _titleCtrl  = TextEditingController();
  late bool _isIncome;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isIncome = widget.isIncome;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(' ', ''));
    if (amount == null || amount <= 0) return;
    final title = _titleCtrl.text.trim().isEmpty
        ? (_isIncome ? 'Доход' : 'Расход')
        : _titleCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await widget.ref.read(transactionProvider.notifier).add(
        title: title,
        amount: amount,
        isIncome: _isIncome,
        date: DateTime.now(),
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _isIncome ? EsepColors.income : EsepColors.expense;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: EsepColors.divider, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),

        // Переключатель Доход / Расход
        Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: EsepColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _isIncome = true),
              child: Container(
                decoration: BoxDecoration(
                  color: _isIncome ? EsepColors.income : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text('Доход',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                        color: _isIncome ? Colors.white : EsepColors.textSecondary)),
              ),
            )),
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _isIncome = false),
              child: Container(
                decoration: BoxDecoration(
                  color: !_isIncome ? EsepColors.expense : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text('Расход',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                        color: !_isIncome ? Colors.white : EsepColors.textSecondary)),
              ),
            )),
          ]),
        ),
        const SizedBox(height: 20),

        // Сумма — большое поле
        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: color),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: TextStyle(fontSize: 36, color: color.withValues(alpha: 0.3)),
            suffixText: '₸',
            suffixStyle: TextStyle(fontSize: 28, color: color),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),

        // Описание
        TextField(
          controller: _titleCtrl,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            hintText: 'Описание (необязательно)',
            prefixIcon: Icon(Icons.notes_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Сохранить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

// ── Deadline Banner ──────────────────────────────────────────────────────────
class _DeadlineBanner extends StatelessWidget {
  const _DeadlineBanner({required this.message, required this.urgent});
  final String message;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? EsepColors.expense : EsepColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(urgent ? Iconsax.warning_2 : Iconsax.clock, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color))),
      ]),
    );
  }
}

// ── Metrics Summary ──────────────────────────────────────────────────────────
class _MetricsSummary extends StatelessWidget {
  const _MetricsSummary({required this.title, required this.income, required this.expense, required this.profit});
  final String title;
  final double income, expense, profit;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _MetricItem(label: 'Доход', amount: income, color: EsepColors.income, fmt: fmt)),
            const SizedBox(width: 1, child: ColoredBox(color: EsepColors.divider, child: SizedBox(height: 36))),
            Expanded(child: _MetricItem(label: 'Расход', amount: expense, color: EsepColors.expense, fmt: fmt)),
            const SizedBox(width: 1, child: ColoredBox(color: EsepColors.divider, child: SizedBox(height: 36))),
            Expanded(child: _MetricItem(
                label: 'Прибыль',
                amount: profit,
                color: profit >= 0 ? EsepColors.primary : EsepColors.expense,
                fmt: fmt)),
          ]),
        ]),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.amount, required this.color, required this.fmt});
  final String label;
  final double amount;
  final Color color;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
    const SizedBox(height: 4),
    Text('${fmt.format(amount)} ₸',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
  ]);
}

// ── Action Button ────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

// ── Event Card ───────────────────────────────────────────────────────────────
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

// ── Monthly Chart ────────────────────────────────────────────────────────────
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.data});
  final List<MonthlyData> data;

  @override
  Widget build(BuildContext context) {
    final maxVal = data.fold(0.0, (m, d) => [m, d.income, d.expense].reduce((a, b) => a > b ? a : b));
    final fmt = NumberFormat.compact(locale: 'ru_RU');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            _Legend(color: EsepColors.income, label: 'Доход'),
            SizedBox(width: 16),
            _Legend(color: EsepColors.expense, label: 'Расход'),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: BarChart(BarChartData(
              maxY: maxVal == 0 ? 100 : maxVal * 1.2,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: EsepColors.divider, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 40,
                  getTitlesWidget: (v, _) => Text(fmt.format(v),
                      style: const TextStyle(fontSize: 9, color: EsepColors.textDisabled)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= data.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(data[i].label,
                          style: const TextStyle(fontSize: 10, color: EsepColors.textSecondary)),
                    );
                  },
                )),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: List.generate(data.length, (i) {
                final d = data[i];
                return BarChartGroupData(x: i, barsSpace: 3, barRods: [
                  BarChartRodData(toY: d.income, color: EsepColors.income, width: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  BarChartRodData(toY: d.expense, color: EsepColors.expense, width: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ]);
              }),
            )),
          ),
        ]),
      ),
    );
  }
}

// ── Tax Forecast Card ─────────────────────────────────────────────────────────
class _TaxForecastCard extends StatelessWidget {
  const _TaxForecastCard({
    required this.halfYearIncome,
    required this.monthIncome,
    required this.socialMonthly,
  });
  final double halfYearIncome;
  final double monthIncome;
  final double socialMonthly;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final taxRate = KzTax.simplified910TotalRate; // 3%
    final halfYearTax = halfYearIncome * taxRate;
    final monthTax = monthIncome * taxRate;
    final monthTotal = monthTax + socialMonthly;

    // Умная подсказка
    String? tip;
    if (halfYearIncome > KzTax.simplified910HalfYearLimit * 0.8) {
      tip = 'Доход приближается к лимиту упрощёнки. Рассмотрите переход на ОУР.';
    } else if (monthIncome > 2000000) {
      tip = 'При доходе > 2М ₸/мес может быть выгоднее другой режим.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Iconsax.calculator, color: EsepColors.primary, size: 18),
            SizedBox(width: 8),
            Text('Налоговый прогноз',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: EsepColors.textPrimary)),
          ]),
          const SizedBox(height: 12),
          // Полугодовой налог
          _ForecastRow(
            label: 'Налог 910 за полугодие (3%)',
            amount: halfYearTax,
            color: EsepColors.expense,
          ),
          const SizedBox(height: 6),
          // Ежемесячно отложить
          _ForecastRow(
            label: 'Налог за этот месяц',
            amount: monthTax,
            color: EsepColors.warning,
          ),
          const SizedBox(height: 6),
          _ForecastRow(
            label: 'Соцплатежи (ОПВ+ОПВР+СО+ВОСМС)',
            amount: socialMonthly,
            color: EsepColors.warning,
          ),
          const Divider(height: 20),
          Row(children: [
            const Icon(Iconsax.wallet_money, color: EsepColors.primary, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Отложить в этом месяце',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Text('${fmt.format(monthTotal)} ₸',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: EsepColors.primary)),
          ]),
          if (tip != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: EsepColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Iconsax.lamp_charge, color: EsepColors.info, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(tip,
                    style: const TextStyle(fontSize: 12, color: EsepColors.info))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.label, required this.amount, required this.color});
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    return Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary))),
      Text('${fmt.format(amount)} ₸',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
  ]);
}
