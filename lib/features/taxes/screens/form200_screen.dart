import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/providers/employees_provider.dart';
import '../../../core/providers/legal_consent_provider.dart';
import '../../../core/services/form200_service.dart';

/// Форма 200.00 — Декларация по ИПН и социальному налогу (квартальная).
class Form200Screen extends ConsumerStatefulWidget {
  const Form200Screen({super.key});

  @override
  ConsumerState<Form200Screen> createState() => _Form200ScreenState();
}

class _Form200ScreenState extends ConsumerState<Form200Screen> {
  late int _quarter;
  late int _year;
  TaxpayerKind _kind = TaxpayerKind.too;
  Form200Data? _result;

  static const _months = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    // По умолчанию — предыдущий завершённый квартал
    final q = ((now.month - 1) ~/ 3) + 1;
    if (q == 1) {
      _quarter = 4;
      _year = now.year - 1;
    } else {
      _quarter = q - 1;
    }
  }

  void _calculate() {
    final company = ref.read(companyProvider);
    final employees = ref.read(employeesProvider);

    final data = Form200Service.calculateUniform(
      iin: company.iin.isNotEmpty ? company.iin : '—',
      fullName: company.name.isNotEmpty ? company.name : 'Налогоплательщик',
      year: _year,
      quarter: _quarter,
      kind: _kind,
      employees: employees,
    );
    setState(() => _result = data);
  }

  Future<void> _export() async {
    final result = _result;
    if (result == null) return;
    final format = await _pickFormat();
    if (format == null) return;

    final consent = ref.read(legalConsentProvider);
    if (!consent.exportDisclaimerDismissed) {
      final ok = await _showPreExportDialog();
      if (ok != true) return;
    }
    await Form200Service.shareFile(result, format);
  }

  Future<Form200Format?> _pickFormat() {
    return showModalBottomSheet<Form200Format>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Формат файла',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Iconsax.document_code, color: EsepColors.primary),
            title: const Text('JSON — КНП ИСНА'),
            subtitle: const Text('Актуальная система на 2026'),
            onTap: () => Navigator.pop(ctx, Form200Format.jsonIsna),
          ),
          ListTile(
            leading: const Icon(Iconsax.document_text),
            title: const Text('XML — СОНО'),
            subtitle: const Text('Старая система, сворачивается'),
            onTap: () => Navigator.pop(ctx, Form200Format.xmlSono),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
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
                  'Проверьте, что все сотрудники и зарплаты внесены за квартал. '
                  'Социальный налог (строка 005) рассчитан по НК 2026 — '
                  'сверьте с бухгалтером перед подачей.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Подача и уплата налога — ваша ответственность '
                  'по Налоговому кодексу РК.',
                  style: TextStyle(
                      fontSize: 12, color: EsepColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: dontShowAgain,
                  onChanged: (v) => setLocal(() => dontShowAgain = v ?? false),
                  title: const Text('Больше не показывать',
                      style: TextStyle(fontSize: 12)),
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
                style: FilledButton.styleFrom(backgroundColor: EsepColors.primary),
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
    final employees = ref.watch(employeesProvider);
    final company = ref.watch(companyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Форма 200.00'),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Iconsax.export_1),
              tooltip: 'Экспорт',
              onPressed: _export,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Подзаголовок
          const Text(
            'Декларация по ИПН и социальному налогу',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Период
          _card(
            title: 'Период',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _quarterSelector()),
                    const SizedBox(width: 12),
                    Expanded(child: _yearSelector()),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Месяцы: ${_result?.monthNumbers.map((m) => _months[m]).join(', ') ?? _quarterMonthsLabel()}',
                    style: const TextStyle(
                        fontSize: 12, color: EsepColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Тип налогоплательщика
          _card(
            title: 'Тип налогоплательщика',
            child: SegmentedButton<TaxpayerKind>(
              segments: const [
                ButtonSegment(value: TaxpayerKind.too, label: Text('ТОО')),
                ButtonSegment(value: TaxpayerKind.ip, label: Text('ИП на ОУР')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _result = null;
              }),
            ),
          ),
          const SizedBox(height: 12),

          // Сотрудники
          _card(
            title: 'Сотрудники (${employees.length})',
            child: employees.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Нет сотрудников. Добавьте их в разделе «Сотрудники» — '
                        'расчёт идёт по их зарплатам за каждый месяц квартала.',
                        style: TextStyle(
                            fontSize: 13, color: EsepColors.textSecondary),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      for (final e in employees)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Iconsax.user,
                                  size: 16, color: EsepColors.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(e.name)),
                              Text('${fmt.format(e.monthlySalary)} ₸/мес',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // Кнопка расчёта
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: EsepColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Iconsax.calculator),
              label: const Text('Рассчитать форму 200',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              onPressed: employees.isEmpty ? null : _calculate,
            ),
          ),

          if (_result != null) ...[
            const SizedBox(height: 20),
            _resultsCard(_result!, fmt),
            const SizedBox(height: 12),
            _snWarning(),
            const SizedBox(height: 12),
            _exportSection(),
          ],

          if (!company.isComplete) ...[
            const SizedBox(height: 16),
            _companyHint(),
          ],
        ],
      ),
    );
  }

  String _quarterMonthsLabel() {
    final start = (_quarter - 1) * 3 + 1;
    return [start, start + 1, start + 2].map((m) => _months[m]).join(', ');
  }

  Widget _quarterSelector() {
    return DropdownButtonFormField<int>(
      initialValue: _quarter,
      decoration: const InputDecoration(labelText: 'Квартал'),
      items: const [
        DropdownMenuItem(value: 1, child: Text('1 квартал')),
        DropdownMenuItem(value: 2, child: Text('2 квартал')),
        DropdownMenuItem(value: 3, child: Text('3 квартал')),
        DropdownMenuItem(value: 4, child: Text('4 квартал')),
      ],
      onChanged: (v) => setState(() {
        _quarter = v ?? _quarter;
        _result = null;
      }),
    );
  }

  Widget _yearSelector() {
    final now = DateTime.now().year;
    return DropdownButtonFormField<int>(
      initialValue: _year,
      decoration: const InputDecoration(labelText: 'Год'),
      items: [
        for (var y = now; y >= now - 3; y--)
          DropdownMenuItem(value: y, child: Text('$y')),
      ],
      onChanged: (v) => setState(() {
        _year = v ?? _year;
        _result = null;
      }),
    );
  }

  Widget _resultsCard(Form200Data d, NumberFormat fmt) {
    final m = d.monthNumbers;
    return _card(
      title: 'Расчёт за ${d.periodLabel}',
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              const Expanded(flex: 5, child: Text('Строка',
                  style: TextStyle(fontSize: 11, color: EsepColors.textSecondary))),
              Expanded(flex: 3, child: Text(_months[m[0]].substring(0, 3),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary))),
              Expanded(flex: 3, child: Text(_months[m[1]].substring(0, 3),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary))),
              Expanded(flex: 3, child: Text(_months[m[2]].substring(0, 3),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary))),
              Expanded(flex: 4, child: Text('Итог',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ],
          ),
          const Divider(height: 16),
          for (final line in d.allLines) _lineRow(line, fmt),
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Итого к перечислению',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Text('${fmt.format(d.grandTotal)} ₸',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: EsepColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineRow(Form200Line line, NumberFormat fmt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${line.code} · ${line.title}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Row(
            children: [
              const Expanded(flex: 5, child: SizedBox()),
              Expanded(flex: 3, child: Text(fmt.format(line.m1),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
              Expanded(flex: 3, child: Text(fmt.format(line.m2),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
              Expanded(flex: 3, child: Text(fmt.format(line.m3),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
              Expanded(flex: 4, child: Text(fmt.format(line.total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _snWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5D87F)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Iconsax.info_circle, color: Color(0xFFB45309), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Строка 005 (СН) рассчитана по формуле НК 2026. Реформа социального '
              'налога ещё уточняется — сверьте сумму с бухгалтером перед подачей. '
              'ИПН, ОПВ, СО, ВОСМС, ООСМС — однозначные ставки.',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF7A5200), height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Iconsax.export_1, color: EsepColors.primary, size: 18),
            SizedBox(width: 8),
            Text('Экспорт декларации',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          const Text(
            'Скачайте файл (JSON — для КНП ИСНА, XML — для старой СОНО) и '
            'загрузите в кабинет со своей ЭЦП.',
            style: TextStyle(fontSize: 12.5, color: EsepColors.textSecondary,
                height: 1.45),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: EsepColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Iconsax.export_3, size: 18),
              label: const Text('Скачать файл декларации'),
              onPressed: _export,
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyHint() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Iconsax.building, color: EsepColors.primary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Заполните реквизиты компании (БИН/ИИН, название) в настройках — '
              'они подставятся в декларацию автоматически.',
              style: TextStyle(fontSize: 12, color: EsepColors.textSecondary,
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
