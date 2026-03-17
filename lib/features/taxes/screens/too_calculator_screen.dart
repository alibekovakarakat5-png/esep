import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';

class TooCalculatorScreen extends StatefulWidget {
  const TooCalculatorScreen({super.key});

  @override
  State<TooCalculatorScreen> createState() => _TooCalculatorScreenState();
}

class _TooCalculatorScreenState extends State<TooCalculatorScreen> {
  double _income = 10000000;
  double _expenses = 6000000;
  bool _isVatPayer = false;
  int _employeeCount = 0;
  double _monthlyPayroll = 0;

  final _incomeController = TextEditingController(text: '10000000');
  final _expensesController = TextEditingController(text: '6000000');
  final _employeeController = TextEditingController(text: '0');
  final _payrollController = TextEditingController(text: '0');
  final _fmt = NumberFormat('#,##0', 'ru_RU');

  @override
  void dispose() {
    _incomeController.dispose();
    _expensesController.dispose();
    _employeeController.dispose();
    _payrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calc = KzTax.calculateToo(
      income: _income,
      expenses: _expenses,
      isVatPayer: _isVatPayer,
      employeeCount: _employeeCount,
      monthlyPayroll: _monthlyPayroll,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Калькулятор ТОО')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Inputs ──────────────────────────────────────────────────────
          const Text(
            'Доход (выручка за период)',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _incomeController,
            decoration: const InputDecoration(
              hintText: 'Введите сумму',
              suffixText: '₸',
              prefixIcon: Icon(Iconsax.money_3, color: EsepColors.income),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final val = double.tryParse(v.replaceAll(' ', ''));
              if (val != null && val >= 0) setState(() => _income = val);
            },
          ),
          const SizedBox(height: 16),

          const Text(
            'Расходы (вычеты)',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _expensesController,
            decoration: const InputDecoration(
              hintText: 'Введите сумму',
              suffixText: '₸',
              prefixIcon: Icon(Iconsax.money_send, color: EsepColors.expense),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final val = double.tryParse(v.replaceAll(' ', ''));
              if (val != null && val >= 0) setState(() => _expenses = val);
            },
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Плательщик НДС', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              'НДС 12%, порог: ${_fmt.format(KzTax.vatRegistrationThreshold)} ₸/год',
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            ),
            value: _isVatPayer,
            onChanged: (v) => setState(() => _isVatPayer = v),
            activeTrackColor: EsepColors.primary,
          ),
          const SizedBox(height: 8),

          const Text(
            'Количество сотрудников',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _employeeController,
            decoration: const InputDecoration(
              hintText: '0',
              prefixIcon: Icon(Iconsax.people, color: EsepColors.primary),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final val = int.tryParse(v.replaceAll(' ', ''));
              if (val != null && val >= 0) setState(() => _employeeCount = val);
            },
          ),
          const SizedBox(height: 16),

          const Text(
            'Средняя зарплата сотрудника',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _payrollController,
            decoration: const InputDecoration(
              hintText: '0',
              suffixText: '₸',
              prefixIcon: Icon(Iconsax.wallet_3, color: EsepColors.warning),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final val = double.tryParse(v.replaceAll(' ', ''));
              if (val != null && val >= 0) setState(() => _monthlyPayroll = val);
            },
          ),
          const SizedBox(height: 24),

          // ─── Card 1: КПН ─────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Iconsax.building_4, color: EsepColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('КПН (20%)', style: TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  const Divider(height: 24),
                  _TaxRow('Доход', _fmt.format(calc.income), EsepColors.income),
                  const SizedBox(height: 8),
                  _TaxRow('Расходы (вычеты)', _fmt.format(calc.expenses), EsepColors.expense),
                  const SizedBox(height: 8),
                  _TaxRow('Налогооблагаемый доход', _fmt.format(calc.taxableIncome), EsepColors.textPrimary),
                  const Divider(height: 24),
                  Row(children: [
                    const Text('КПН (20%)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      '${_fmt.format(calc.kpn)} ₸',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EsepColors.expense),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Card 2: НДС (только если плательщик) ────────────────────────
          if (_isVatPayer) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Iconsax.receipt_2, color: EsepColors.info, size: 20),
                      SizedBox(width: 8),
                      Text('НДС (12%)', style: TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    const Divider(height: 24),
                    _TaxRow('НДС получен (с дохода)', _fmt.format(calc.vatReceived), EsepColors.income),
                    const SizedBox(height: 8),
                    _TaxRow('НДС уплачен (с расходов)', _fmt.format(calc.vatPaid), EsepColors.expense),
                    const Divider(height: 24),
                    Row(children: [
                      const Text('НДС к уплате', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                        '${_fmt.format(calc.vatPayable)} ₸',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EsepColors.expense),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Card 3: Соц. налог (только если есть сотрудники) ────────────
          if (_employeeCount > 0) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Iconsax.people, color: EsepColors.warning, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Соц. налог за сотрудников (9.5%)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                    const Divider(height: 24),
                    _TaxRow('Средняя зарплата', _fmt.format(_monthlyPayroll), EsepColors.textPrimary),
                    const SizedBox(height: 8),
                    _TaxRow(
                      'ОПВ (10%)',
                      _fmt.format(_monthlyPayroll * KzTax.employeeOpvRate),
                      EsepColors.warning,
                    ),
                    const SizedBox(height: 8),
                    _TaxRow(
                      'База СН (ЗП - ОПВ)',
                      _fmt.format(_monthlyPayroll - _monthlyPayroll * KzTax.employeeOpvRate),
                      EsepColors.textSecondary,
                    ),
                    const SizedBox(height: 8),
                    _TaxRow('Кол-во сотрудников', '$_employeeCount', EsepColors.textPrimary),
                    const Divider(height: 24),
                    Row(children: [
                      const Expanded(
                        child: Text(
                          'Соц. налог / мес',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${_fmt.format(calc.socialTax)} ₸',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EsepColors.warning),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'В год: ${_fmt.format(calc.socialTax * 12)} ₸',
                      style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Card 4: Дивиденды ──────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Iconsax.money_recive, color: EsepColors.income, size: 20),
                    SizedBox(width: 8),
                    Text('Дивиденды (5%)', style: TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  const Divider(height: 24),
                  _TaxRow('Чистая прибыль', _fmt.format(calc.netProfit), EsepColors.income),
                  const SizedBox(height: 8),
                  _TaxRow('ИПН с дивидендов (5%)', _fmt.format(calc.dividendTax), EsepColors.expense),
                  const Divider(height: 24),
                  Row(children: [
                    const Expanded(
                      child: Text(
                        'На руки учредителю',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${_fmt.format(calc.netProfit - calc.dividendTax)} ₸',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EsepColors.income),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Card 5: Итого ──────────────────────────────────────────────
          Card(
            color: EsepColors.info.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SummaryRow('Доход', '${_fmt.format(calc.income)} ₸', EsepColors.textPrimary),
                  const Divider(height: 16, color: EsepColors.divider),
                  _SummaryRow('КПН', '${_fmt.format(calc.kpn)} ₸', EsepColors.expense),
                  if (_isVatPayer) ...[
                    const Divider(height: 16, color: EsepColors.divider),
                    _SummaryRow('НДС к уплате', '${_fmt.format(calc.vatPayable)} ₸', EsepColors.expense),
                  ],
                  const Divider(height: 16, color: EsepColors.divider),
                  _SummaryRow('ИПН с дивидендов', '${_fmt.format(calc.dividendTax)} ₸', EsepColors.expense),
                  const Divider(height: 16, color: EsepColors.divider),
                  _SummaryRow('Всего налогов', '${_fmt.format(calc.totalTax)} ₸', EsepColors.expense),
                  const Divider(height: 16, color: EsepColors.divider),
                  _SummaryRow(
                    'Эффективная ставка',
                    '${(calc.effectiveRate * 100).toStringAsFixed(1)}%',
                    EsepColors.warning,
                  ),
                  const Divider(height: 16, color: EsepColors.divider),
                  _SummaryRow(
                    'Чистыми после всех налогов',
                    '${_fmt.format(calc.netProfit - calc.dividendTax)} ₸',
                    EsepColors.income,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Виджеты
// ═══════════════════════════════════════════════════════════════════════════════

class _TaxRow extends StatelessWidget {
  const _TaxRow(this.label, this.amount, this.color);
  final String label, amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: EsepColors.textSecondary),
          ),
        ),
        Text(
          '$amount ₸',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
        ),
      ]);
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, this.valueColor);
  final String label, value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: valueColor),
        ),
      ]);
}
