import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/providers/legal_consent_provider.dart';
import '../../../core/services/form300_service.dart';

/// Форма 300.00 — Декларация по НДС (квартальная).
class Form300Screen extends ConsumerStatefulWidget {
  const Form300Screen({super.key});

  @override
  ConsumerState<Form300Screen> createState() => _Form300ScreenState();
}

class _Form300ScreenState extends ConsumerState<Form300Screen> {
  late int _quarter;
  late int _year;
  bool _amountsIncludeVat = false;

  final _salesCtrl = TextEditingController();
  final _purchaseCtrl = TextEditingController();

  Form300Data? _result;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    final q = ((now.month - 1) ~/ 3) + 1;
    if (q == 1) {
      _quarter = 4;
      _year = now.year - 1;
    } else {
      _quarter = q - 1;
    }
  }

  @override
  void dispose() {
    _salesCtrl.dispose();
    _purchaseCtrl.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;

  void _calculate() {
    final company = ref.read(companyProvider);
    final data = Form300Service.calculate(
      iin: company.iin.isNotEmpty ? company.iin : '—',
      fullName: company.name.isNotEmpty ? company.name : 'Налогоплательщик',
      year: _year,
      quarter: _quarter,
      salesAmount: _parse(_salesCtrl),
      purchaseAmount: _parse(_purchaseCtrl),
      amountsIncludeVat: _amountsIncludeVat,
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
    await Form300Service.shareFile(result, format);
  }

  Future<Form300Format?> _pickFormat() {
    return showModalBottomSheet<Form300Format>(
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
            onTap: () => Navigator.pop(ctx, Form300Format.jsonIsna),
          ),
          ListTile(
            leading: const Icon(Iconsax.document_text),
            title: const Text('XML — СОНО'),
            subtitle: const Text('Старая система, сворачивается'),
            onTap: () => Navigator.pop(ctx, Form300Format.xmlSono),
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
                  'MVP расчёт НДS: оборот реализации минус оборот приобретения. '
                  'Приложения (нулевая ставка, импорт, освобождённые обороты, '
                  'пропорциональный зачёт) пока не входят — при необходимости '
                  'дозаполните в кабинете.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Подача и уплата налога — ваша ответственность по НК РК.',
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
    final vatPct = (KzTax.vatRate * 100).toStringAsFixed(0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Форма 300.00'),
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
          Text(
            'Декларация по НДС · ставка $vatPct% (НК 2026)',
            style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 16),

          _card(
            title: 'Период',
            child: Row(
              children: [
                Expanded(child: _quarterSelector()),
                const SizedBox(width: 12),
                Expanded(child: _yearSelector()),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _card(
            title: 'Обороты за квартал',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Оборот по реализации (продажи)',
                    style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _salesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Сумма продаж за квартал',
                    suffixText: '₸',
                    prefixIcon: Icon(Iconsax.trend_up, color: EsepColors.income),
                  ),
                  onChanged: (_) => setState(() => _result = null),
                ),
                const SizedBox(height: 14),
                const Text('Оборот по приобретению (покупки с НДС)',
                    style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _purchaseCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Сумма покупок за квартал',
                    suffixText: '₸',
                    prefixIcon: Icon(Iconsax.trend_down, color: EsepColors.expense),
                  ),
                  onChanged: (_) => setState(() => _result = null),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Суммы указаны с НДС',
                      style: TextStyle(fontSize: 13)),
                  subtitle: Text(
                    _amountsIncludeVat
                        ? 'НДС выделим изнутри (÷ 1.$vatPct)'
                        : 'НДС начислим сверху (× $vatPct%)',
                    style: const TextStyle(fontSize: 11,
                        color: EsepColors.textSecondary),
                  ),
                  value: _amountsIncludeVat,
                  onChanged: (v) => setState(() {
                    _amountsIncludeVat = v;
                    _result = null;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: EsepColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Iconsax.calculator),
              label: const Text('Рассчитать НДС',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              onPressed: _calculate,
            ),
          ),

          if (_result != null) ...[
            const SizedBox(height: 20),
            _resultsCard(_result!, fmt),
            const SizedBox(height: 12),
            _mvpWarning(),
            const SizedBox(height: 12),
            _exportSection(),
          ],
        ],
      ),
    );
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

  Widget _resultsCard(Form300Data d, NumberFormat fmt) {
    final toPay = d.vatPayable > 0;
    return _card(
      title: 'Расчёт за ${d.periodLabel}',
      child: Column(
        children: [
          _row('Оборот реализации (300.00.006)', '${fmt.format(d.salesTurnover)} ₸'),
          _row('НДС начислен (300.00.012)', '${fmt.format(d.outputVat)} ₸',
              color: EsepColors.income),
          const Divider(height: 18),
          _row('Оборот приобретения (300.00.021)', '${fmt.format(d.purchaseTurnover)} ₸'),
          _row('НДС в зачёт (300.00.023)', '${fmt.format(d.inputVat)} ₸',
              color: EsepColors.expense),
          const Divider(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: toPay
                  ? EsepColors.expense.withValues(alpha: 0.08)
                  : EsepColors.income.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    toPay
                        ? 'НДС к уплате (300.00.030 I)'
                        : 'Превышение зачёта (300.00.030 II)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                Text(
                  '${fmt.format(toPay ? d.vatPayable : d.vatExcess)} ₸',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: toPay ? EsepColors.expense : EsepColors.income,
                  ),
                ),
              ],
            ),
          ),
          if (!toPay && d.vatExcess > 0)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Превышение можно зачесть в следующем периоде или заявить '
                'к возврату (отдельная процедура).',
                style: TextStyle(fontSize: 11.5, color: EsepColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: color ?? EsepColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _mvpWarning() {
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
              'Базовый расчёт: НДС начислен − НДС в зачёт. Не включены: '
              'нулевая ставка (экспорт), импорт, освобождённые обороты, '
              'пропорциональный зачёт. Для сложных случаев — сверьте с бухгалтером.',
              style: TextStyle(fontSize: 12, color: Color(0xFF7A5200), height: 1.45),
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
            'Скачайте файл (JSON — КНП ИСНА, XML — СОНО) и загрузите в '
            'кабинет со своей ЭЦП.',
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
