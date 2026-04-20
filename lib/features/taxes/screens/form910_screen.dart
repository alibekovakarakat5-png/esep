import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/services/form910_service.dart';

class Form910Screen extends ConsumerStatefulWidget {
  const Form910Screen({super.key});

  @override
  ConsumerState<Form910Screen> createState() => _Form910ScreenState();
}

class _Form910ScreenState extends ConsumerState<Form910Screen> {
  late int _halfYear;
  late int _year;
  int _employeeCount = 0;
  double _totalPayroll = 0;
  bool _bornBefore1975 = false;
  Form910Data? _result;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    // Default to previous half-year (most common use case)
    if (now.month <= 6) {
      _halfYear = 2;
      _year = now.year - 1;
    } else {
      _halfYear = 1;
    }
  }

  void _calculate() {
    final transactions = ref.read(transactionProvider);
    final company = ref.read(companyProvider);

    final data = Form910Service.calculate(
      transactions: transactions,
      company: company,
      halfYear: _halfYear,
      year: _year,
      employeeCount: _employeeCount,
      totalPayroll: _totalPayroll,
      bornBefore1975: _bornBefore1975,
    );

    setState(() => _result = data);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final company = ref.watch(companyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Форма 910.00'),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Iconsax.document_upload),
              tooltip: 'Экспорт XML',
              onPressed: () => Form910Service.shareXml(_result!),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Company info warning
          if (!company.isComplete)
            Card(
              color: EsepColors.warning.withValues(alpha: 0.1),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Iconsax.warning_2, color: EsepColors.warning, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text(
                    'Заполните данные ИП в настройках (ИИН, название)',
                    style: TextStyle(fontSize: 12, color: EsepColors.warning),
                  )),
                ]),
              ),
            ),
          if (!company.isComplete) const SizedBox(height: 12),

          // Period selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Период', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _halfYear,
                      decoration: const InputDecoration(
                        labelText: 'Полугодие',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1-е (янв-июн)')),
                        DropdownMenuItem(value: 2, child: Text('2-е (июл-дек)')),
                      ],
                      onChanged: (v) => setState(() {
                        _halfYear = v!;
                        _result = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _year,
                      decoration: const InputDecoration(
                        labelText: 'Год',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        for (var y = DateTime.now().year; y >= 2024; y--)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (v) => setState(() {
                        _year = v!;
                        _result = null;
                      }),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Employee info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Сотрудники', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Кол-во сотрудников',
                        hintText: '0',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        _employeeCount = int.tryParse(v) ?? 0;
                        _result = null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Средняя з/п, ₸',
                        hintText: '0',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        _totalPayroll = double.tryParse(v.replaceAll(' ', '')) ?? 0;
                        _result = null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Родился до 1975 года', style: TextStyle(fontSize: 13)),
                  value: _bornBefore1975,
                  onChanged: (v) => setState(() {
                    _bornBefore1975 = v;
                    _result = null;
                  }),
                  activeTrackColor: EsepColors.primary,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Calculate button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _calculate,
              icon: const Icon(Iconsax.calculator),
              label: const Text('Рассчитать форму 910'),
              style: FilledButton.styleFrom(
                backgroundColor: EsepColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Results
          if (_result != null) ...[
            _ResultCard(data: _result!, fmt: fmt),
            const SizedBox(height: 12),
            _SocialCard(data: _result!, fmt: fmt),
            const SizedBox(height: 12),
            _TotalCard(data: _result!, fmt: fmt),
            const SizedBox(height: 16),

            // Export buttons
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Form910Service.shareXml(_result!),
                  icon: const Icon(Iconsax.document_code, size: 18),
                  label: const Text('XML'),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // Submit to cabinet.kgd.gov.kz
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Iconsax.export_1, color: EsepColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text('Подать форму 910', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  const Text(
                    '1. Скачайте XML-файл выше\n'
                    '2. Войдите в Кабинет налогоплательщика\n'
                    '3. Загрузите XML или заполните вручную',
                    style: TextStyle(fontSize: 12, color: EsepColors.textSecondary, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://cabinet.kgd.gov.kz'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Iconsax.export_3, size: 18),
                      label: const Text('Открыть cabinet.kgd.gov.kz'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://sono.kgd.gov.kz'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Iconsax.document_upload, size: 16),
                      label: const Text('Или через СОНО', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data, required this.fmt});
  final Form910Data data;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Iconsax.calculator, color: EsepColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Налоги (${data.periodLabel})',
                style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const Divider(height: 24),
          _FormRow('910.00.001', 'Доход за период', fmt.format(data.income)),
          _FormRow('910.00.001A', 'Безналичные расчёты', fmt.format(data.incomeNonCash)),
          _FormRow('910.00.003', 'Среднесп. работников', data.avgEmployees.toStringAsFixed(0)),
          _FormRow('910.00.004', 'Средняя з/п', fmt.format(data.avgMonthlyWage)),
          const Divider(height: 16),
          _FormRow('910.00.005', 'Налог с дохода (4%)', fmt.format(data.calculatedTax)),
          _FormRow('910.00.006', 'Корректировка налога', fmt.format(data.taxAdjustment)),
          _FormRow('910.00.007', 'Итого налогов', fmt.format(data.netTax), bold: true),
          const Divider(height: 16),
          _FormRow('910.00.008', 'Подоходный налог (4%)', fmt.format(data.ipn), color: EsepColors.expense),
          _FormRow('910.00.009', 'Социальный налог (0%)', fmt.format(data.socialTax), color: EsepColors.expense),
        ]),
      ),
    );
  }
}

class _SocialCard extends StatelessWidget {
  const _SocialCard({required this.data, required this.fmt});
  final Form910Data data;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Iconsax.people, color: EsepColors.warning, size: 20),
            SizedBox(width: 8),
            Text('Обязательные взносы (за 6 мес)',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const Divider(height: 24),
          _FormRow('910.00.010', 'База для соцстрахования', fmt.format(data.soIncome)),
          _FormRow('910.00.011', 'Соцстрахование (5%)', fmt.format(data.soAmount), color: EsepColors.warning),
          _FormRow('910.00.012', 'База для пенсионных', fmt.format(data.opvIncome)),
          _FormRow('910.00.013', 'Пенсия (10%)', fmt.format(data.opvAmount), color: EsepColors.warning),
          _FormRow('910.00.014', 'Пенсия от работодателя (3.5%)', fmt.format(data.opvrAmount), color: EsepColors.warning),
          _FormRow('910.00.015', 'Медстрахование', fmt.format(data.vosmsAmount), color: EsepColors.warning),
        ]),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.data, required this.fmt});
  final Form910Data data;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: EsepColors.expense.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            const Text('Налоги', style: TextStyle(fontSize: 14)),
            const Spacer(),
            Text('${fmt.format(data.totalTax)} ₸',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: EsepColors.expense)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Text('Обязательные взносы', style: TextStyle(fontSize: 14)),
            const Spacer(),
            Text('${fmt.format(data.totalSocial)} ₸',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: EsepColors.warning)),
          ]),
          const Divider(height: 20),
          Row(children: [
            const Text('ИТОГО к оплате', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${fmt.format(data.grandTotal)} ₸',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: EsepColors.expense)),
          ]),
        ]),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow(this.code, this.label, this.value, {this.bold = false, this.color});
  final String code;
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        // Field codes hidden for simplicity
        Expanded(
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: EsepColors.textSecondary,
              )),
        ),
        Text('$value ₸',
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? EsepColors.textPrimary,
            )),
      ]),
    );
  }
}
