import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/employee.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/providers/employees_provider.dart';
import '../../../core/providers/legal_consent_provider.dart';
import '../../../core/services/form910_service.dart';

class Form910Screen extends ConsumerStatefulWidget {
  const Form910Screen({super.key});

  @override
  ConsumerState<Form910Screen> createState() => _Form910ScreenState();
}

class _Form910ScreenState extends ConsumerState<Form910Screen> {
  late int _halfYear;
  late int _year;

  // Ручной override: если null — берём авто из сотрудников.
  int? _manualEmployeeCount;
  double? _manualAvgSalary;
  bool _bornBefore1975 = false;

  final _employeeCountCtrl = TextEditingController();
  final _avgSalaryCtrl = TextEditingController();

  Form910Data? _result;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    if (now.month <= 6) {
      _halfYear = 2;
      _year = now.year - 1;
    } else {
      _halfYear = 1;
    }
  }

  @override
  void dispose() {
    _employeeCountCtrl.dispose();
    _avgSalaryCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final transactions = ref.read(transactionProvider);
    final company = ref.read(companyProvider);
    final summary = ref.read(
      payrollSummaryProvider((year: _year, halfYear: _halfYear)),
    );

    // Эффективные значения: ручной ввод либо авто из сотрудников
    final headcount = _manualEmployeeCount ?? summary.avgHeadcount.round();
    final avgSalary = _manualAvgSalary ?? summary.avgWagePerWorker;
    // Form910Service делит totalPayroll на employeeCount, чтобы получить avgMonthlyWage.
    // Передаём totalPayroll = avgSalary * headcount, чтобы деление вернуло среднюю ЗП.
    final totalPayroll = avgSalary * headcount;

    final data = Form910Service.calculate(
      transactions: transactions,
      company: company,
      halfYear: _halfYear,
      year: _year,
      employeeCount: headcount,
      totalPayroll: totalPayroll,
      bornBefore1975: _bornBefore1975,
    );

    setState(() => _result = data);
  }

  Future<void> _exportXml() async {
    final result = _result;
    if (result == null) return;

    final consent = ref.read(legalConsentProvider);
    if (!consent.exportDisclaimerDismissed) {
      final ok = await _showPreExportDialog();
      if (ok != true) return;
    }
    await Form910Service.shareXml(result);
  }

  Future<bool?> _showPreExportDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool dontShowAgain = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Row(children: [
              Icon(Iconsax.shield_tick, color: EsepColors.primary, size: 22),
              SizedBox(width: 10),
              Expanded(child: Text('Перед подачей')),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Проверьте, что все доходы и сотрудники внесены за период. '
                  'Расчёт основан только на введённых данных.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Подача и уплата налога — ваша ответственность '
                  'по Налоговому кодексу РК.',
                  style: TextStyle(
                    fontSize: 12,
                    color: EsepColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: dontShowAgain,
                  onChanged: (v) => setLocal(() => dontShowAgain = v ?? false),
                  title: const Text(
                    'Больше не показывать',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () async {
                  if (dontShowAgain) {
                    await ref
                        .read(legalConsentProvider.notifier)
                        .dismissExportDisclaimer();
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                style:
                    FilledButton.styleFrom(backgroundColor: EsepColors.primary),
                child: const Text('Экспортировать'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final company = ref.watch(companyProvider);
    final summary = ref.watch(
      payrollSummaryProvider((year: _year, halfYear: _halfYear)),
    );
    final employees = ref.watch(employeesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Форма 910.00'),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Iconsax.document_upload),
              tooltip: 'Экспорт XML',
              onPressed: _exportXml,
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

          // Employees — auto-filled card
          _EmployeesCard(
            summary: summary,
            hasEmployees: employees.isNotEmpty,
            manualEmployeeCount: _manualEmployeeCount,
            manualAvgSalary: _manualAvgSalary,
            employeeCountCtrl: _employeeCountCtrl,
            avgSalaryCtrl: _avgSalaryCtrl,
            bornBefore1975: _bornBefore1975,
            fmt: fmt,
            onManualEmployeeCountChanged: (v) {
              _manualEmployeeCount = v;
              _result = null;
              setState(() {});
            },
            onManualSalaryChanged: (v) {
              _manualAvgSalary = v;
              _result = null;
              setState(() {});
            },
            onUseAuto: () {
              setState(() {
                _manualEmployeeCount = null;
                _manualAvgSalary = null;
                _employeeCountCtrl.clear();
                _avgSalaryCtrl.clear();
                _result = null;
              });
            },
            onBornChanged: (v) => setState(() {
              _bornBefore1975 = v;
              _result = null;
            }),
            onManageEmployees: () => context.push('/employees'),
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
                  onPressed: _exportXml,
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

// ─── Auto-filled Employees Card ─────────────────────────────────────────────

class _EmployeesCard extends StatelessWidget {
  const _EmployeesCard({
    required this.summary,
    required this.hasEmployees,
    required this.manualEmployeeCount,
    required this.manualAvgSalary,
    required this.employeeCountCtrl,
    required this.avgSalaryCtrl,
    required this.bornBefore1975,
    required this.fmt,
    required this.onManualEmployeeCountChanged,
    required this.onManualSalaryChanged,
    required this.onUseAuto,
    required this.onBornChanged,
    required this.onManageEmployees,
  });

  final PayrollPeriodSummary summary;
  final bool hasEmployees;
  final int? manualEmployeeCount;
  final double? manualAvgSalary;
  final TextEditingController employeeCountCtrl;
  final TextEditingController avgSalaryCtrl;
  final bool bornBefore1975;
  final NumberFormat fmt;
  final ValueChanged<int?> onManualEmployeeCountChanged;
  final ValueChanged<double?> onManualSalaryChanged;
  final VoidCallback onUseAuto;
  final ValueChanged<bool> onBornChanged;
  final VoidCallback onManageEmployees;

  @override
  Widget build(BuildContext context) {
    final isOverridden =
        manualEmployeeCount != null || manualAvgSalary != null;
    final autoAvailable = summary.hasData;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Iconsax.people, size: 18, color: EsepColors.primary),
            const SizedBox(width: 8),
            const Text('Сотрудники',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: onManageEmployees,
              icon: const Icon(Iconsax.setting_2, size: 16),
              label: const Text('Управление', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
          const SizedBox(height: 4),

          // Статус: авто/ручной ввод/нет данных
          if (autoAvailable && !isOverridden)
            _AutoBadge(summary: summary, fmt: fmt)
          else if (isOverridden)
            _OverrideBadge(onReset: onUseAuto, hasAuto: autoAvailable)
          else
            _NoDataBadge(onAdd: onManageEmployees),

          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: TextField(
                controller: employeeCountCtrl,
                decoration: InputDecoration(
                  labelText: 'Кол-во сотрудников',
                  hintText: autoAvailable
                      ? summary.avgHeadcount.toStringAsFixed(0)
                      : '0',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  onManualEmployeeCountChanged(parsed);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: avgSalaryCtrl,
                decoration: InputDecoration(
                  labelText: 'Средняя з/п, ₸',
                  hintText: autoAvailable
                      ? fmt.format(summary.avgWagePerWorker)
                      : '0',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final cleaned = v.replaceAll(' ', '');
                  final parsed = double.tryParse(cleaned);
                  onManualSalaryChanged(parsed);
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Родился до 1975 года',
                style: TextStyle(fontSize: 13)),
            value: bornBefore1975,
            onChanged: onBornChanged,
            activeTrackColor: EsepColors.primary,
          ),
        ]),
      ),
    );
  }
}

class _AutoBadge extends StatelessWidget {
  const _AutoBadge({required this.summary, required this.fmt});
  final PayrollPeriodSummary summary;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final headcount = summary.avgHeadcount.toStringAsFixed(1);
    final wage = fmt.format(summary.avgWagePerWorker);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: EsepColors.income.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Iconsax.magicpen, color: EsepColors.income, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Авто: $headcount чел. · $wage ₸ средняя',
            style: const TextStyle(
              fontSize: 12,
              color: EsepColors.income,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }
}

class _OverrideBadge extends StatelessWidget {
  const _OverrideBadge({required this.onReset, required this.hasAuto});
  final VoidCallback onReset;
  final bool hasAuto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EsepColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Iconsax.edit_2, color: EsepColors.warning, size: 16),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Ручной ввод',
            style: TextStyle(
              fontSize: 12,
              color: EsepColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (hasAuto)
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Авто', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}

class _NoDataBadge extends StatelessWidget {
  const _NoDataBadge({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: EsepColors.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(children: [
          Icon(Iconsax.info_circle, color: EsepColors.info, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Добавьте сотрудников → поля заполнятся сами',
              style: TextStyle(fontSize: 12, color: EsepColors.info),
            ),
          ),
          Icon(Iconsax.arrow_right_3, color: EsepColors.info, size: 14),
        ]),
      ),
    );
  }
}

// ─── Result cards (без изменений) ───────────────────────────────────────────

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
