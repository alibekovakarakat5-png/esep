import 'dart:math';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';

class SalaryCalculatorScreen extends StatefulWidget {
  const SalaryCalculatorScreen({super.key});

  @override
  State<SalaryCalculatorScreen> createState() => _SalaryCalculatorScreenState();
}

class _SalaryCalculatorScreenState extends State<SalaryCalculatorScreen> {
  double _salary = 250000;
  bool _bornBefore1975 = false;
  final _controller = TextEditingController(text: '250000');
  final _fmt = NumberFormat('#,##0', 'ru_RU');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ─── Employee deductions ──────────────────────────────────────────────────
    final opvBase = min(_salary, KzTax.currentMzp * 50);
    final opv = opvBase * KzTax.employeeOpvRate;

    final mrpDeduction = KzTax.ipnMonthlyDeduction; // 30 МРП (Новый НК РК 2026)
    final ipnTaxable = max(0.0, _salary - opv - mrpDeduction);
    final ipn = ipnTaxable * KzTax.generalIpnRate; // 10% (до 8500 МРП)

    final vosmsEmployeeBase = min(_salary, KzTax.currentMzp * 20);
    final vosmsEmployee = vosmsEmployeeBase * KzTax.employeeVosmsRate;

    final totalDeductions = opv + ipn + vosmsEmployee;
    final netPay = _salary - totalDeductions;

    // ─── Employer costs ───────────────────────────────────────────────────────
    final soBase = max(KzTax.currentMzp, min(_salary - opv, KzTax.currentMzp * 7));
    final so = soBase * KzTax.employerSoRate;

    final opvrBase = min(_salary, KzTax.currentMzp * 50);
    final opvr = _bornBefore1975 ? 0.0 : opvrBase * KzTax.employerOpvrRate;

    final oosmsBase = min(_salary, KzTax.currentMzp * 40);
    final oosms = oosmsBase * KzTax.employerVosmsRate;

    final totalEmployerCosts = so + opvr + oosms;
    final totalCostForCompany = _salary + totalEmployerCosts;

    return Scaffold(
      appBar: AppBar(title: const Text('Зарплатный калькулятор')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Input ────────────────────────────────────────────────────────
          const Text(
            'Начисленная зарплата (gross)',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'Введите сумму',
              suffixText: '₸',
              prefixIcon: Icon(Iconsax.money_3, color: EsepColors.income),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final val = double.tryParse(v.replaceAll(' ', ''));
              if (val != null && val >= 0) setState(() => _salary = val);
            },
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Родился до 1975 года', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              'ОПВР не начисляется',
              style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            ),
            value: _bornBefore1975,
            onChanged: (v) => setState(() => _bornBefore1975 = v),
            activeTrackColor: EsepColors.primary,
          ),
          const SizedBox(height: 16),

          // ─── Section 1: Employee deductions ───────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Iconsax.profile_delete, color: EsepColors.expense, size: 20),
                    SizedBox(width: 8),
                    Text('Удержания с работника', style: TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  const Divider(height: 24),
                  _TaxRow(
                    'ОПВ (10%)',
                    _fmt.format(opv),
                    EsepColors.expense,
                  ),
                  const SizedBox(height: 8),
                  _TaxRow(
                    'ИПН (10%)',
                    _fmt.format(ipn),
                    EsepColors.expense,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 0, top: 2, bottom: 8),
                    child: Text(
                      'База: ${_fmt.format(_salary)} - ${_fmt.format(opv)} (ОПВ) - ${_fmt.format(mrpDeduction)} (14 МРП) = ${_fmt.format(ipnTaxable)} ₸',
                      style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary),
                    ),
                  ),
                  _TaxRow(
                    'ВОСМС работника (2%)',
                    _fmt.format(vosmsEmployee),
                    EsepColors.expense,
                  ),
                  const Divider(height: 24),
                  _TaxRow(
                    'Итого удержания',
                    _fmt.format(totalDeductions),
                    EsepColors.expense,
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Text(
                      'На руки (net)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '${_fmt.format(netPay)} ₸',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EsepColors.income,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Section 2: Employer costs ────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Iconsax.building, color: EsepColors.warning, size: 20),
                    SizedBox(width: 8),
                    Text('Расходы работодателя', style: TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  const Divider(height: 24),
                  _TaxRow(
                    'СО (5%)',
                    _fmt.format(so),
                    EsepColors.warning,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      'База: ЗП - ОПВ, мин 1 МЗП, макс 7 МЗП',
                      style: TextStyle(fontSize: 11, color: EsepColors.textSecondary),
                    ),
                  ),
                  if (!_bornBefore1975) ...[
                    _TaxRow(
                      'ОПВР (3.5%)',
                      _fmt.format(opvr),
                      EsepColors.warning,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_bornBefore1975) ...[
                    const _TaxRow(
                      'ОПВР',
                      '0',
                      EsepColors.textSecondary,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 2, bottom: 8),
                      child: Text(
                        'Не начисляется (год рождения до 1975)',
                        style: TextStyle(fontSize: 11, color: EsepColors.textSecondary),
                      ),
                    ),
                  ],
                  _TaxRow(
                    'ООСМС (3%)',
                    _fmt.format(oosms),
                    EsepColors.warning,
                  ),
                  const Divider(height: 24),
                  _TaxRow(
                    'Итого расходы',
                    _fmt.format(totalEmployerCosts),
                    EsepColors.warning,
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Expanded(
                      child: Text(
                        'Полная стоимость сотрудника',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${_fmt.format(totalCostForCompany)} ₸',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EsepColors.expense,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Summary ──────────────────────────────────────────────────────
          Card(
            color: EsepColors.info.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SummaryRow(
                    'Начислено',
                    '${_fmt.format(_salary)} ₸',
                    EsepColors.textPrimary,
                  ),
                  const Divider(height: 16, color: EsepColors.divider),
                  _SummaryRow(
                    'На руки',
                    '${_fmt.format(netPay)} ₸',
                    EsepColors.income,
                  ),
                  const Divider(height: 16, color: EsepColors.divider),
                  _SummaryRow(
                    'Стоимость для компании',
                    '${_fmt.format(totalCostForCompany)} ₸',
                    EsepColors.expense,
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
