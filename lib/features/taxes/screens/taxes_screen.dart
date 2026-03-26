import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  bool _bornBefore1975 = false;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');

    return Scaffold(
      appBar: AppBar(title: const Text('Налоги')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Быстрые инструменты
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            final buttonWidth = wide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: buttonWidth,
                  child: _ToolButton(
                    icon: Iconsax.document_text,
                    label: 'Форма 910',
                    onTap: () => context.push('/form-910'),
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: _ToolButton(
                    icon: Iconsax.people,
                    label: 'Зарплатный калькулятор',
                    onTap: () => context.push('/salary-calculator'),
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: _ToolButton(
                    icon: Iconsax.building_4,
                    label: 'Калькулятор ТОО',
                    onTap: () => context.push('/too-calculator'),
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: _ToolButton(
                    icon: Iconsax.search_normal_1,
                    label: 'Поиск по БИН',
                    onTap: () => context.push('/bin-lookup'),
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: _ToolButton(
                    icon: Iconsax.book_1,
                    label: 'Гид по режимам',
                    onTap: () => context.push('/regime-guide'),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 16),

          // Баннер о реформе 2026
          _ReformBanner(),
          const SizedBox(height: 16),

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
          const SizedBox(height: 16),

          // Переключатель ОПВР
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Родился до 1975 года', style: TextStyle(fontSize: 14)),
            subtitle: const Text('ОПВР не начисляется', style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
            value: _bornBefore1975,
            onChanged: (v) => setState(() => _bornBefore1975 = v),
            activeTrackColor: EsepColors.primary,
          ),
          const SizedBox(height: 16),

          // Расчёт по выбранному режиму
          if (_regime == TaxRegime.simplified) ...[
            _SimplifiedCard(income: _income, bornBefore1975: _bornBefore1975, fmt: fmt),
            const SizedBox(height: 16),
            _SocialPaymentsCard(bornBefore1975: _bornBefore1975, fmt: fmt),
            const SizedBox(height: 16),
            const _DeadlineCard(),
          ],
          if (_regime == TaxRegime.esp) _EspCard(fmt: fmt),
          if (_regime == TaxRegime.selfEmployed)
            _SelfEmployedCard(income: _income, fmt: fmt),
          if (_regime == TaxRegime.general)
            _GeneralCard(income: _income, fmt: fmt),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Виджеты
// ═══════════════════════════════════════════════════════════════════════════════

class _ReformBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
        color: EsepColors.info.withValues(alpha: 0.08),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Iconsax.info_circle, color: EsepColors.info, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ставки обновлены по НК 2026: упрощёнка 3%, СО 5%, добавлены ОПВР и ВОСМС',
                  style: TextStyle(fontSize: 12, color: EsepColors.info),
                ),
              ),
            ],
          ),
        ),
      );
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

class _SimplifiedCard extends StatelessWidget {
  const _SimplifiedCard({required this.income, required this.bornBefore1975, required this.fmt});
  final double income;
  final bool bornBefore1975;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final full = KzTax.calculateFull910(income, bornBefore1975: bornBefore1975);
    final tax = full.tax;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Iconsax.calculator, color: EsepColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Упрощёнка (910) — 3%', style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const Divider(height: 24),
          _TaxRow('Доход за полугодие', fmt.format(tax.income), EsepColors.textPrimary),
          const SizedBox(height: 8),
          _TaxRow('ИПН (${(tax.effectiveIpnRate * 100).toStringAsFixed(0)}%)', fmt.format(tax.ipn), EsepColors.expense),
          const SizedBox(height: 8),
          _TaxRow('СН (${(tax.effectiveSnRate * 100).toStringAsFixed(0)}%)', fmt.format(tax.sn), EsepColors.expense),
          const Divider(height: 24),
          Row(children: [
            const Text('Налоги по 910', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${fmt.format(tax.totalTax)} ₸',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EsepColors.expense)),
          ]),
          const SizedBox(height: 4),
          _TaxRow('+ Соцплатежи (6 мес)', fmt.format(full.socialHalfYear), EsepColors.warning),
          const Divider(height: 24),
          Row(children: [
            const Text('Итого за полугодие', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${fmt.format(full.grandTotal)} ₸',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EsepColors.expense)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Эффективная ставка: ${(full.effectiveRate * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
          ),
        ]),
      ),
    );
  }
}

class _SocialPaymentsCard extends StatelessWidget {
  const _SocialPaymentsCard({required this.bornBefore1975, required this.fmt});
  final bool bornBefore1975;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final social = KzTax.calculateMonthlySocial(bornBefore1975: bornBefore1975);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Iconsax.calendar_1, color: EsepColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Ежемесячно "за себя"', style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          const Text('Платить до 25 числа следующего месяца',
              style: TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
          const Divider(height: 24),
          _TaxRow('ОПВ (10% от МЗП)', fmt.format(social.opv), EsepColors.warning),
          const SizedBox(height: 8),
          if (!bornBefore1975) ...[
            _TaxRow('ОПВР (3.5% от МЗП)', fmt.format(social.opvr), EsepColors.warning),
            const SizedBox(height: 8),
          ],
          _TaxRow('СО (5% от МЗП)', fmt.format(social.so), EsepColors.warning),
          const SizedBox(height: 8),
          _TaxRow('ВОСМС (5% от 1.4 МЗП)', fmt.format(social.vosms), EsepColors.warning),
          const Divider(height: 24),
          Row(children: [
            const Text('Итого в месяц', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${fmt.format(social.total)} ₸',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: EsepColors.expense)),
          ]),
          const SizedBox(height: 4),
          Text('В год: ${fmt.format(social.total * 12)} ₸',
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _TaxRow extends StatelessWidget {
  const _TaxRow(this.label, this.amount, this.color);
  final String label, amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: EsepColors.textSecondary))),
        Text('$amount ₸', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ]);
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard();

  @override
  Widget build(BuildContext context) => Card(
        color: EsepColors.warning.withValues(alpha: 0.08),
        child: const ListTile(
          leading: Icon(Iconsax.calendar_tick, color: EsepColors.warning),
          title: Text('Сроки 910 формы', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
            '1 полугодие: подать до 15 авг, оплатить до 25 авг\n'
            '2 полугодие: подать до 15 фев, оплатить до 25 фев\n'
            '⚠ С 2026 отзыв деклараций запрещён!',
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
            const SizedBox(height: 8),
            _TaxRow('В год (город)', fmt.format(KzTax.espMonthlyCity * 12), EsepColors.expense),
            const Divider(height: 20),
            Text('Лимит дохода: ${fmt.format(KzTax.espYearLimit)} ₸/год',
                style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
            const SizedBox(height: 4),
            Text('МРП 2026: ${fmt.format(KzTax.currentMrp)} ₸',
                style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          ]),
        ),
      );
}

class _SelfEmployedCard extends StatelessWidget {
  const _SelfEmployedCard({required this.income, required this.fmt});
  final double income;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final tax = KzTax.calculateSelfEmployed(income);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Iconsax.user_tick, color: EsepColors.primary, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Самозанятый (замена патента с 2026)', style: TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: EsepColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Iconsax.info_circle, color: EsepColors.warning, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Патент ликвидирован с 01.01.2026. Новый режим самозанятых: ставка 4%',
                style: TextStyle(fontSize: 11, color: EsepColors.warning),
              )),
            ]),
          ),
          const Divider(height: 24),
          _TaxRow('Доход', fmt.format(income), EsepColors.textPrimary),
          const SizedBox(height: 8),
          _TaxRow('Налог (4%)', fmt.format(tax), EsepColors.expense),
          const Divider(height: 20),
          Text('Лимит дохода: ${fmt.format(KzTax.selfEmployedYearLimit)} ₸/год',
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _GeneralCard extends StatelessWidget {
  const _GeneralCard({required this.income, required this.fmt});
  final double income;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final ipn = KzTax.calculateProgressiveIpn(income);
    final rateLabel = income > KzTax.generalIpnThreshold ? '10-15%' : '10%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Iconsax.building_4, color: EsepColors.primary, size: 20),
            SizedBox(width: 8),
            Text('ОУР — Общеустановленный режим', style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const Divider(height: 24),
          _TaxRow('Чистый доход', fmt.format(income), EsepColors.textPrimary),
          const SizedBox(height: 8),
          _TaxRow('ИПН ($rateLabel)', fmt.format(ipn), EsepColors.expense),
          const Divider(height: 20),
          const Text(
            'ОУР: без лимита дохода. ИПН 10% от чистого дохода (доход − вычеты).\n'
            'Обязателен при превышении лимитов упрощёнки.',
            style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text('Порог НДС: ${fmt.format(KzTax.vatRegistrationThreshold)} ₸/год',
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: EsepColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              children: [
                Icon(icon, color: EsepColors.primary, size: 28),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: EsepColors.primary),
                ),
              ],
            ),
          ),
        ),
      );
}
