import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/diagnosis.dart';
import '../../../core/models/tax_profile.dart';
import '../../../core/services/diagnosis_service.dart';
import 'diagnosis_report_screen.dart';

/// Step-by-step онбординг «Что изменилось для меня в 2026».
///
/// 6 шагов:
///   1. Кто вы (ИП / ТОО / Физлицо)
///   2. Налоговый режим
///   3. Есть ли наёмные + сколько
///   4. Годовой доход (диапазон)
///   5. НДС + год рождения (ОПВР)
///   6. Email (опционально — для сохранения отчёта/лида)
class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  int _step = 0;

  // ── Ответы ─────────────────────────────────────────────────────────────────
  EntityType _entityType = EntityType.ip;
  TaxRegimeKind _regime = TaxRegimeKind.simplified910;
  bool _hasEmployees = false;
  int _employeesCount = 1;
  double _averageSalary = 150000;
  double _annualRevenue = 5000000; // ~5 млн ₸/год
  bool _isVatPayer = false;
  bool _bornBefore1975 = false;

  static const _stepsCount = 5;

  // Диапазоны дохода
  static const _revenueOptions = <(double, String)>[
    (2000000,    'до 2 млн ₸ (старт)'),
    (8000000,    '2-15 млн ₸ (стабильный фриланс)'),
    (40000000,   '15-65 млн ₸ (малый бизнес)'),
    (200000000,  '65-300 млн ₸ (растущий бизнес)'),
    (1000000000, '300 млн — 2.6 млрд ₸ (крупный)'),
    (3000000000, 'свыше 2.6 млрд ₸ (выйдет из 910)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Что изменилось для меня в 2026'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Позже'),
          ),
        ],
      ),
      body: Column(
        children: [
          _progressBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: _buildStep(),
            ),
          ),
          _bottomNav(),
        ],
      ),
    );
  }

  // ── Progress bar ────────────────────────────────────────────────────────────

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: List.generate(_stepsCount, (i) {
          final done = i <= _step;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == _stepsCount - 1 ? 0 : 4),
              height: 4,
              decoration: BoxDecoration(
                color: done ? EsepColors.primary : EsepColors.textDisabled.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Steps ───────────────────────────────────────────────────────────────────

  Widget _buildStep() {
    switch (_step) {
      case 0: return _step1EntityType();
      case 1: return _step2Regime();
      case 2: return _step3Employees();
      case 3: return _step4Revenue();
      case 4: return _step5Misc();
      default: return const SizedBox.shrink();
    }
  }

  Widget _step1EntityType() => _StepFrame(
    title: 'Кто вы по форме регистрации?',
    subtitle: 'От этого зависит какие налоги и формы применяются.',
    children: [
      _RadioCard<EntityType>(
        value: EntityType.ip,
        groupValue: _entityType,
        onChanged: (v) => setState(() => _entityType = v!),
        icon: Iconsax.user,
        title: 'ИП',
        subtitle: 'Индивидуальный предприниматель',
      ),
      _RadioCard<EntityType>(
        value: EntityType.too,
        groupValue: _entityType,
        onChanged: (v) => setState(() => _entityType = v!),
        icon: Iconsax.building,
        title: 'ТОО',
        subtitle: 'Юридическое лицо',
      ),
      _RadioCard<EntityType>(
        value: EntityType.individual,
        groupValue: _entityType,
        onChanged: (v) => setState(() {
          _entityType = v!;
          _regime = TaxRegimeKind.selfEmployed;
        }),
        icon: Iconsax.profile_2user,
        title: 'Физлицо / самозанятый',
        subtitle: 'Без регистрации ИП',
      ),
    ],
  );

  Widget _step2Regime() {
    final available = _availableRegimes();
    return _StepFrame(
      title: 'Какой налоговый режим?',
      subtitle: 'Если не уверены — выберите упрощёнку (910), это самый частый.',
      children: available.map((r) => _RadioCard<TaxRegimeKind>(
        value: r,
        groupValue: _regime,
        onChanged: (v) => setState(() => _regime = v!),
        icon: _regimeIcon(r),
        title: r.label,
        subtitle: _regimeHint(r),
      )).toList(),
    );
  }

  Widget _step3Employees() {
    return _StepFrame(
      title: 'Есть наёмные сотрудники?',
      subtitle: 'Сотрудники — это самые большие изменения 2026 года '
          '(ОПВР, СО, СН).',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Есть наёмные сотрудники'),
          subtitle: Text(
            _hasEmployees ? 'Считаем нагрузку на ФОТ' : 'Только за себя',
            style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
          ),
          value: _hasEmployees,
          onChanged: (v) => setState(() => _hasEmployees = v),
        ),
        if (_hasEmployees) ...[
          const SizedBox(height: 16),
          _NumberField(
            label: 'Сколько сотрудников',
            value: _employeesCount.toDouble(),
            min: 1,
            onChanged: (v) => setState(() => _employeesCount = v.round()),
            isInteger: true,
          ),
          const SizedBox(height: 12),
          _NumberField(
            label: 'Средняя зарплата на руки, ₸/мес',
            value: _averageSalary,
            min: 85000,
            step: 10000,
            onChanged: (v) => setState(() => _averageSalary = v),
          ),
        ],
      ],
    );
  }

  Widget _step4Revenue() {
    return _StepFrame(
      title: 'Ориентировочный годовой доход',
      subtitle: 'Можно округлить. Это нужно чтобы посчитать дельту в тенге.',
      children: _revenueOptions.map((opt) => _RadioCard<double>(
        value: opt.$1,
        groupValue: _annualRevenue,
        onChanged: (v) => setState(() => _annualRevenue = v!),
        icon: Iconsax.money_3,
        title: opt.$2,
        subtitle: 'Берём середину диапазона для расчёта',
      )).toList(),
    );
  }

  Widget _step5Misc() {
    final showVat = _regime == TaxRegimeKind.general || _regime == TaxRegimeKind.retail;
    final showOpvr = _entityType == EntityType.ip;
    return _StepFrame(
      title: 'Несколько уточнений',
      subtitle: 'Эти галочки сильно влияют на расчёт.',
      children: [
        if (showVat)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Плательщик НДС'),
            subtitle: const Text(
              'Если состоите на учёте по НДС — переключите',
              style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            ),
            value: _isVatPayer,
            onChanged: (v) => setState(() => _isVatPayer = v),
          ),
        if (showOpvr)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Родились до 1975 года'),
            subtitle: const Text(
              'Тогда ОПВР за себя не платите',
              style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            ),
            value: _bornBefore1975,
            onChanged: (v) => setState(() => _bornBefore1975 = v),
          ),
        if (!showVat && !showOpvr)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Дополнительных уточнений для вас нет — переходите к отчёту.',
              style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
            ),
          ),
      ],
    );
  }

  // ── Bottom nav ──────────────────────────────────────────────────────────────

  Widget _bottomNav() {
    final isLast = _step == _stepsCount - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                child: const Text('Назад'),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: Icon(isLast ? Iconsax.chart_2 : Iconsax.arrow_right_3, size: 18),
              label: Text(isLast ? 'Получить отчёт' : 'Дальше'),
              onPressed: () {
                if (isLast) {
                  _goToReport();
                } else {
                  setState(() => _step++);
                }
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _goToReport() {
    final answers = DiagnosisAnswers(
      entityType: _entityType,
      regime: _regime,
      hasEmployees: _hasEmployees,
      employeesCount: _hasEmployees ? _employeesCount : 0,
      averageSalary: _averageSalary,
      annualRevenue: _annualRevenue,
      isVatPayer: _isVatPayer,
      bornBefore1975: _bornBefore1975,
    );
    final report = DiagnosisService.calculate(answers);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DiagnosisReportScreen(report: report),
    ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<TaxRegimeKind> _availableRegimes() {
    switch (_entityType) {
      case EntityType.individual:
        return [TaxRegimeKind.selfEmployed, TaxRegimeKind.esp];
      case EntityType.ip:
        return [
          TaxRegimeKind.simplified910,
          TaxRegimeKind.general,
          TaxRegimeKind.selfEmployed,
          TaxRegimeKind.retail,
        ];
      case EntityType.too:
        return [TaxRegimeKind.simplified910, TaxRegimeKind.general, TaxRegimeKind.retail];
    }
  }

  IconData _regimeIcon(TaxRegimeKind r) {
    switch (r) {
      case TaxRegimeKind.simplified910: return Iconsax.document_text;
      case TaxRegimeKind.general:       return Iconsax.calculator;
      case TaxRegimeKind.selfEmployed:  return Iconsax.profile_2user;
      case TaxRegimeKind.esp:           return Iconsax.wallet_2;
      case TaxRegimeKind.retail:        return Iconsax.shop;
    }
  }

  String _regimeHint(TaxRegimeKind r) {
    switch (r) {
      case TaxRegimeKind.simplified910: return '4% от дохода, отчёт раз в полугодие';
      case TaxRegimeKind.general:       return 'КПН 20% (ТОО) / прогрессивный ИПН (ИП) + НДС если оборот выше порога';
      case TaxRegimeKind.selfEmployed:  return '4% от дохода, лимит 3 600 МРП/год';
      case TaxRegimeKind.esp:           return 'Фиксированный платёж в МРП ежемесячно';
      case TaxRegimeKind.retail:        return 'Розничный налог 4% (специальный режим)';
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ────────────────────────────────────────────────────────────────────────────

class _StepFrame extends StatelessWidget {
  const _StepFrame({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(fontSize: 14, color: EsepColors.textSecondary, height: 1.4)),
          const SizedBox(height: 20),
          ...children,
        ],
      );
}

class _RadioCard<T> extends StatelessWidget {
  const _RadioCard({
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final T groupValue;
  final ValueChanged<T?> onChanged;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? EsepColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? EsepColors.primary
                  : EsepColors.textDisabled.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: (selected ? EsepColors.primary : EsepColors.textSecondary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: selected ? EsepColors.primary : EsepColors.textSecondary,
                  size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              ]),
            ),
            Radio<T>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: EsepColors.primary,
            ),
          ]),
        ),
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.step = 1,
    this.isInteger = false,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double step;
  final bool isInteger;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl;

  static final _intFmt = NumberFormat('#,##0', 'ru_RU');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.isInteger
          ? widget.value.round().toString()
          : _intFmt.format(widget.value),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Iconsax.money_3, size: 18),
      ),
      onChanged: (s) {
        final clean = s.replaceAll(RegExp(r'[^0-9]'), '');
        final v = double.tryParse(clean) ?? widget.min;
        widget.onChanged(v < widget.min ? widget.min : v);
      },
    );
  }
}
