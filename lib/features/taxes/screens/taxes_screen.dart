import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';

class TaxesScreen extends StatefulWidget {
  const TaxesScreen({super.key});

  @override
  State<TaxesScreen> createState() => _TaxesScreenState();
}

class _TaxesScreenState extends State<TaxesScreen> {
  TaxRegime _regime = TaxRegime.simplified;
  double _income = 1250000;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final calc = KzTax.calculate910(_income);

    return Scaffold(
      appBar: AppBar(title: const Text('Налоги')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Налоговый режим', style: TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
          const SizedBox(height: 8),
          _RegimePicker(selected: _regime, onChanged: (r) => setState(() => _regime = r)),
          const SizedBox(height: 24),
          const Text('Доход за период', style: TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              hintText: fmt.format(_income),
              suffixText: '₸',
              prefixIcon: const Icon(Iconsax.money_3, color: EsepColors.income),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final val = double.tryParse(v.replaceAll(' ', ''));
              if (val != null) setState(() => _income = val);
            },
          ),
          const SizedBox(height: 24),
          if (_regime == TaxRegime.simplified) ...[
            _TaxBreakdownCard(calc: calc, fmt: fmt),
            const SizedBox(height: 16),
            _DeadlineCard(),
          ],
          if (_regime == TaxRegime.esp) _EspCard(fmt: fmt),
          if (_regime == TaxRegime.patent) _PatentCard(income: _income, fmt: fmt),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _RegimePicker extends StatelessWidget {
  const _RegimePicker({required this.selected, required this.onChanged});
  final TaxRegime selected;
  final ValueChanged<TaxRegime> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: TaxRegime.values.map((r) {
          final active = r == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(r.shortName),
              selected: active,
              onSelected: (_) => onChanged(r),
              selectedColor: EsepColors.primary.withValues(alpha: 0.15),
              checkmarkColor: EsepColors.primary,
              labelStyle: TextStyle(
                color: active ? EsepColors.primary : EsepColors.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TaxBreakdownCard extends StatelessWidget {
  const _TaxBreakdownCard({required this.calc, required this.fmt});
  final TaxCalculation calc;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Iconsax.calculator, color: EsepColors.primary, size: 20),
              SizedBox(width: 8),
              Text('Расчёт — Упрощёнка (910)', style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const Divider(height: 24),
            _TaxRow('Доход', fmt.format(calc.income), EsepColors.textPrimary),
            const SizedBox(height: 8),
            _TaxRow('ИПН (1.5%)', fmt.format(calc.ipn), EsepColors.expense),
            const SizedBox(height: 8),
            _TaxRow('СН (1.5%)', fmt.format(calc.sn), EsepColors.expense),
            const SizedBox(height: 8),
            _TaxRow('ОПВ (10%)', fmt.format(calc.opv), EsepColors.warning),
            const SizedBox(height: 8),
            _TaxRow('СО (3.5%)', fmt.format(calc.so), EsepColors.warning),
            const Divider(height: 24),
            Row(children: [
              const Text('Итого к уплате', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${fmt.format(calc.total)} ₸',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EsepColors.expense)),
            ]),
            const SizedBox(height: 8),
            Text(
              'Эффективная ставка: ${(calc.effectiveRate * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            ),
          ]),
        ),
      );
}

class _TaxRow extends StatelessWidget {
  const _TaxRow(this.label, this.amount, this.color);
  final String label, amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label, style: const TextStyle(fontSize: 14, color: EsepColors.textSecondary)),
        const Spacer(),
        Text('$amount ₸', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ]);
}

class _DeadlineCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
        color: EsepColors.warning.withValues(alpha: 0.08),
        child: const ListTile(
          leading: Icon(Iconsax.calendar_tick, color: EsepColors.warning),
          title: Text('Срок сдачи', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
            '1 полугодие: до 15 августа 2025\n2 полугодие: до 15 февраля 2026',
            style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
          ),
          trailing: Icon(Iconsax.notification_1, color: EsepColors.warning, size: 20),
          isThreeLine: true,
        ),
      );
}

class _EspCard extends StatelessWidget {
  const _EspCard({required this.fmt});
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ЕСП — Единый совокупный платёж', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _TaxRow('В городе (1 МРП/мес)', fmt.format(KzTax.espMonthlyCity), EsepColors.expense),
            const SizedBox(height: 8),
            _TaxRow('В селе (0.5 МРП/мес)', fmt.format(KzTax.espMonthlyRural), EsepColors.expense),
            const Divider(height: 20),
            Text('Лимит дохода: ${fmt.format(KzTax.espYearLimit)} ₸/год',
                style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          ]),
        ),
      );
}

class _PatentCard extends StatelessWidget {
  const _PatentCard({required this.income, required this.fmt});
  final double income;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final tax = KzTax.calculatePatent(income);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Патент (1% от заявленного дохода)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _TaxRow('Заявленный доход', fmt.format(income), EsepColors.textPrimary),
          const SizedBox(height: 8),
          _TaxRow('Налог (1%)', fmt.format(tax), EsepColors.expense),
          const Divider(height: 20),
          Text('Лимит дохода: ${fmt.format(KzTax.patentYearLimit)} ₸/год',
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
        ]),
      ),
    );
  }
}
