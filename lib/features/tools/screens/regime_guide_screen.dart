import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';

/// Тип организации
enum _EntityType { ip, too }

class RegimeGuideScreen extends ConsumerStatefulWidget {
  const RegimeGuideScreen({super.key});

  @override
  ConsumerState<RegimeGuideScreen> createState() => _RegimeGuideScreenState();
}

class _RegimeGuideScreenState extends ConsumerState<RegimeGuideScreen> {
  _EntityType _entityType = _EntityType.ip;
  TaxRegime _regime = TaxRegime.simplified;

  bool _reportsExpanded = true;
  bool _paymentsExpanded = false;
  bool _deadlinesExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final type = GoRouterState.of(context).uri.queryParameters['type'];
    if (type == 'too') {
      _entityType = _EntityType.too;
      _regime = TaxRegime.general;
    } else if (type == 'ip') {
      _entityType = _EntityType.ip;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой налоговый режим'),
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Entity type selector ---
            const Text(
              'Форма организации',
              style: TextStyle(fontSize: 13, color: EsepColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('ИП'),
                  selected: _entityType == _EntityType.ip,
                  onSelected: (_) => setState(() {
                    _entityType = _EntityType.ip;
                    _regime = TaxRegime.simplified;
                  }),
                  selectedColor: EsepColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: EsepColors.primary,
                  labelStyle: TextStyle(
                    color: _entityType == _EntityType.ip
                        ? EsepColors.primary
                        : EsepColors.textSecondary,
                    fontWeight: _entityType == _EntityType.ip
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('ТОО'),
                  selected: _entityType == _EntityType.too,
                  onSelected: (_) => setState(() {
                    _entityType = _EntityType.too;
                    _regime = TaxRegime.general;
                  }),
                  selectedColor: EsepColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: EsepColors.primary,
                  labelStyle: TextStyle(
                    color: _entityType == _EntityType.too
                        ? EsepColors.primary
                        : EsepColors.textSecondary,
                    fontWeight: _entityType == _EntityType.too
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- Regime selector (only for IP) ---
            if (_entityType == _EntityType.ip) ...[
              const Text(
                'Налоговый режим',
                style:
                    TextStyle(fontSize: 13, color: EsepColors.textSecondary),
              ),
              const SizedBox(height: 8),
              _RegimePicker(
                selected: _regime,
                onChanged: (r) => setState(() => _regime = r),
              ),
              const SizedBox(height: 16),
            ],

            // --- Info banner ---
            Card(
              color: EsepColors.info.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Iconsax.info_circle,
                        color: EsepColors.info, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _entityType == _EntityType.too
                            ? 'ТОО работает на общеустановленном режиме (ОУР)'
                            : 'Выбран режим: ${_regime.fullName}',
                        style: const TextStyle(
                            fontSize: 12, color: EsepColors.info),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Card 1: Reports ---
            _buildExpandableCard(
              icon: Iconsax.document_text,
              title: 'Какие отчёты сдавать',
              expanded: _reportsExpanded,
              onToggle: () =>
                  setState(() => _reportsExpanded = !_reportsExpanded),
              child: _buildReportsContent(),
            ),
            const SizedBox(height: 12),

            // --- Card 2: Monthly payments ---
            _buildExpandableCard(
              icon: Iconsax.money_send,
              title: 'Ежемесячные платежи',
              expanded: _paymentsExpanded,
              onToggle: () =>
                  setState(() => _paymentsExpanded = !_paymentsExpanded),
              child: _buildPaymentsContent(fmt),
            ),
            const SizedBox(height: 12),

            // --- Card 3: Deadlines ---
            _buildExpandableCard(
              icon: Iconsax.calendar_tick,
              title: 'Ближайшие дедлайны',
              expanded: _deadlinesExpanded,
              onToggle: () =>
                  setState(() => _deadlinesExpanded = !_deadlinesExpanded),
              child: _buildDeadlinesContent(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Expandable card wrapper
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExpandableCard({
    required IconData icon,
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: expanded
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: EsepColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: EsepColors.textPrimary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Iconsax.arrow_down_1,
                        size: 20, color: EsepColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Card 1: Reports content
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReportsContent() {
    if (_entityType == _EntityType.too) {
      return _buildTooReports();
    }

    switch (_regime) {
      case TaxRegime.simplified:
        return _buildSimplifiedReports();
      case TaxRegime.esp:
        return _buildEspReports();
      case TaxRegime.selfEmployed:
        return _buildSelfEmployedReports();
      case TaxRegime.general:
        return _buildGeneralIpReports();
    }
  }

  Widget _buildSimplifiedReports() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _reportItem(
          'Форма 910.00',
          '2 раза в год (за каждое полугодие)',
          Iconsax.document_1,
        ),
        const SizedBox(height: 10),
        _deadlineRow('I полугодие', 'сдать до 15 августа'),
        _deadlineRow('II полугодие', 'сдать до 15 февраля'),
        const SizedBox(height: 10),
        _whereToSubmit('cabinet.salyk.kz (нужна ЭЦП)'),
      ],
    );
  }

  Widget _buildEspReports() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EsepColors.income.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Iconsax.tick_circle, color: EsepColors.income, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Отчётов нет!\nОплата через приложение e-Salyk Azamat каждый месяц.',
                  style: TextStyle(fontSize: 13, color: EsepColors.income),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelfEmployedReports() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EsepColors.income.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Iconsax.tick_circle, color: EsepColors.income, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Отчётов нет!\nОплата через e-Salyk Azamat.',
                  style: TextStyle(fontSize: 13, color: EsepColors.income),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralIpReports() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _reportItem(
          'Форма 220.00 (ИПН)',
          'Ежеквартально',
          Iconsax.document_1,
        ),
        const SizedBox(height: 6),
        _deadlineRow('Сроки', '15 мая, 15 авг, 15 ноя, 15 фев'),
        const SizedBox(height: 10),
        _reportItem(
          'Форма 200.00 (если есть сотрудники)',
          'Ежеквартально',
          Iconsax.people,
        ),
        const SizedBox(height: 10),
        _whereToSubmit('cabinet.salyk.kz (нужна ЭЦП)'),
      ],
    );
  }

  Widget _buildTooReports() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Налоговые формы ---
        const Text('Налоговая отчётность (salyk.kz):',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: EsepColors.primary)),
        const SizedBox(height: 8),
        ...KzTax.tooTaxForms.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _reportItem(
                    'Форма ${f.code} — ${f.name}',
                    '${f.frequency} • ${f.deadlineDescription}',
                    f.code == '100.00'
                        ? Iconsax.document_1
                        : f.code == '300.00'
                            ? Iconsax.receipt_2
                            : Iconsax.people,
                  ),
                ],
              ),
            )),
        _whereToSubmit('cabinet.salyk.kz (нужна ЭЦП)'),
        const SizedBox(height: 16),

        // --- Статистические формы ---
        const Text('Комитет статистики (stat.gov.kz):',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: EsepColors.primary)),
        const SizedBox(height: 8),
        ...KzTax.tooStatForms.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _reportItem(
                '${f.code} — ${f.name}',
                '${f.frequency} • ${f.deadlineDescription}',
                Iconsax.chart_1,
              ),
            )),
        _whereToSubmit('stat.gov.kz (кабинет респондента, нужна ЭЦП)'),
      ],
    );
  }

  Widget _reportItem(String title, String subtitle, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: EsepColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: EsepColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _deadlineRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12,
                  color: EsepColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, color: EsepColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _whereToSubmit(String place) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EsepColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.monitor, size: 16, color: EsepColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Где сдавать: $place',
              style: const TextStyle(fontSize: 12, color: EsepColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Card 2: Monthly payments content
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPaymentsContent(NumberFormat fmt) {
    if (_entityType == _EntityType.too) {
      return _buildTooPayments(fmt);
    }

    switch (_regime) {
      case TaxRegime.simplified:
      case TaxRegime.general:
        return _buildIpSelfPayments(fmt);
      case TaxRegime.esp:
        return _buildEspPayments(fmt);
      case TaxRegime.selfEmployed:
        return _buildSelfEmployedPayments(fmt);
    }
  }

  Widget _buildIpSelfPayments(NumberFormat fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ИП за себя (ежемесячно):',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _paymentRow('ОПВ (10% от МЗП)', fmt.format(KzTax.opvMonthly)),
        _paymentRow('ОПВР (3.5% от МЗП)', fmt.format(KzTax.opvrMonthly)),
        _paymentRow('СО (5% от МЗП)', fmt.format(KzTax.soMonthly)),
        _paymentRow(
            'ВОСМС (5% от 1.4 x МЗП)', fmt.format(KzTax.vosmsMonthly)),
        const Divider(height: 20),
        Row(
          children: [
            const Text('Итого',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${fmt.format(KzTax.monthlyTotalSelf)} \u20b8/мес',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EsepColors.expense)),
          ],
        ),
        const SizedBox(height: 8),
        _deadlineBadge('Срок оплаты: до 25 числа каждого месяца'),
      ],
    );
  }

  Widget _buildEspPayments(NumberFormat fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paymentRow(
            'Город (1 МРП/мес)', fmt.format(KzTax.espMonthlyCity)),
        _paymentRow(
            'Село (0.5 МРП/мес)', fmt.format(KzTax.espMonthlyRural)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: EsepColors.income.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Включает ОПВ + СО + ВОСМС + ИПН — всё в одном платеже!',
            style: TextStyle(fontSize: 12, color: EsepColors.income),
          ),
        ),
        const SizedBox(height: 8),
        _deadlineBadge('Срок оплаты: до 25 числа каждого месяца'),
      ],
    );
  }

  Widget _buildSelfEmployedPayments(NumberFormat fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Налог с дохода:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _paymentRow('4% от дохода', 'ИПН + СН'),
        const SizedBox(height: 12),
        const Text('Соцплатежи дополнительно (ежемесячно):',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _paymentRow('ОПВ (10% от МЗП)', fmt.format(KzTax.opvMonthly)),
        _paymentRow('ОПВР (3.5% от МЗП)', fmt.format(KzTax.opvrMonthly)),
        _paymentRow('СО (5% от МЗП)', fmt.format(KzTax.soMonthly)),
        _paymentRow(
            'ВОСМС (5% от 1.4 x МЗП)', fmt.format(KzTax.vosmsMonthly)),
        const Divider(height: 20),
        Row(
          children: [
            const Text('Итого соцплатежи',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${fmt.format(KzTax.monthlyTotalSelf)} \u20b8/мес',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EsepColors.expense)),
          ],
        ),
        const SizedBox(height: 8),
        _deadlineBadge('Срок оплаты: до 25 числа каждого месяца'),
      ],
    );
  }

  Widget _buildTooPayments(NumberFormat fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Основные налоги:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _paymentRow(
            'КПН', '20% от прибыли (авансы ежемесячно/ежеквартально)'),
        _paymentRow(
            'НДС (если плательщик)', '16% (оборот > 10 000 МРП)'),
        const SizedBox(height: 12),
        const Text('За сотрудников:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _paymentRow('ОПВ', '10%'),
        _paymentRow('ИПН', '10-15%'),
        _paymentRow('СН', '6%'),
        _paymentRow('СО', '5%'),
        _paymentRow('ОПВР', '3.5%'),
        _paymentRow('ВОСМС работник', '2%'),
        _paymentRow('ООСМС работодатель', '3%'),
        const SizedBox(height: 8),
        _deadlineBadge('Срок оплаты: до 25 числа каждого месяца'),
      ],
    );
  }

  Widget _paymentRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: EsepColors.textSecondary)),
          ),
          Text('$value \u20b8',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EsepColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _deadlineBadge(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EsepColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.clock, size: 16, color: EsepColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 12, color: EsepColors.warning)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Card 3: Deadlines content
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDeadlinesContent() {
    final now = DateTime.now();
    final deadlines = _getDeadlines(now);

    // Sort by date, take nearest 5
    deadlines.sort((a, b) => a.date.compareTo(b.date));
    final nearest = deadlines.take(5).toList();

    if (nearest.isEmpty) {
      return const Text('Нет ближайших дедлайнов',
          style: TextStyle(fontSize: 13, color: EsepColors.textSecondary));
    }

    return Column(
      children: nearest.map((d) {
        final daysLeft = d.date.difference(now).inDays;
        final color = daysLeft < 3
            ? EsepColors.expense
            : daysLeft < 7
                ? EsepColors.warning
                : EsepColors.income;
        final label = daysLeft < 0
            ? 'Просрочен!'
            : daysLeft == 0
                ? 'Сегодня!'
                : '$daysLeft дн.';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                      '${d.date.day}.${d.date.month.toString().padLeft(2, '0')}.${d.date.year}',
                      style: const TextStyle(
                          fontSize: 11, color: EsepColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<_Deadline> _getDeadlines(DateTime now) {
    final deadlines = <_Deadline>[];
    final year = now.year;

    // Social payments: 25th of every month (current + next months)
    for (var m = now.month; m <= now.month + 3 && m <= 12; m++) {
      final date = DateTime(year, m, 25);
      if (!date.isBefore(now)) {
        deadlines.add(_Deadline('Соцплатежи за ${_monthName(m - 1 == 0 ? 12 : m - 1)}', date));
      }
    }
    // Handle year boundary for social payments
    if (now.month >= 10) {
      for (var m = 1; m <= 3; m++) {
        final date = DateTime(year + 1, m, 25);
        deadlines.add(_Deadline('Соцплатежи за ${_monthName(m - 1 == 0 ? 12 : m - 1)}', date));
      }
    }

    if (_entityType == _EntityType.ip) {
      switch (_regime) {
        case TaxRegime.simplified:
          // 910 form deadlines
          _addIfFuture(deadlines, DateTime(year, 8, 15),
              'Форма 910.00 (I полугодие)', now);
          _addIfFuture(deadlines, DateTime(year + 1, 2, 15),
              'Форма 910.00 (II полугодие)', now);
          _addIfFuture(deadlines, DateTime(year, 2, 15),
              'Форма 910.00 (II полугодие ${year - 1})', now);
        case TaxRegime.esp:
          // No report deadlines, only social payments
          break;
        case TaxRegime.selfEmployed:
          // No report deadlines, only social payments
          break;
        case TaxRegime.general:
          // Quarterly 220.00
          for (final d in [
            DateTime(year, 5, 15),
            DateTime(year, 8, 15),
            DateTime(year, 11, 15),
            DateTime(year + 1, 2, 15),
          ]) {
            _addIfFuture(deadlines, d, 'Форма 220.00 (ИПН)', now);
          }
      }
    } else {
      // TOO — налоговые формы
      for (final f in KzTax.tooTaxForms) {
        for (final m in f.deadlineMonths) {
          final y = m < now.month ? year + 1 : year;
          _addIfFuture(
              deadlines, DateTime(y, m, f.deadlineDay), 'Форма ${f.code}', now);
        }
      }

      // TOO — статистические формы
      for (final f in KzTax.tooStatForms) {
        for (final m in f.deadlineMonths) {
          final y = m < now.month ? year + 1 : year;
          _addIfFuture(
              deadlines, DateTime(y, m, f.deadlineDay), '${f.code} (stat.gov.kz)', now);
        }
      }
    }

    return deadlines;
  }

  void _addIfFuture(
      List<_Deadline> list, DateTime date, String title, DateTime now) {
    // Include deadlines from 7 days ago to catch overdue items
    if (date.isAfter(now.subtract(const Duration(days: 7)))) {
      list.add(_Deadline(title, date));
    }
  }

  String _monthName(int month) {
    const names = [
      '', 'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
      'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
    ];
    return names[month.clamp(1, 12)];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helper types & widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _Deadline {
  final String title;
  final DateTime date;
  const _Deadline(this.title, this.date);
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
