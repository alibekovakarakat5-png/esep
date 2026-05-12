import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/diagnosis.dart';
import '../../../core/models/tax_profile.dart';

/// Итоговый отчёт: «что изменилось для вас в 2026»
class DiagnosisReportScreen extends StatelessWidget {
  const DiagnosisReportScreen({super.key, required this.report});

  final DiagnosisReport report;

  static final _fmt = NumberFormat('#,##0', 'ru_RU');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ваш отчёт за 2026'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.copy),
            tooltip: 'Скопировать',
            onPressed: () => _copyToClipboard(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(),
          const SizedBox(height: 20),
          _profileChip(),
          const SizedBox(height: 24),
          const Text('Изменения, которые вас касаются',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...report.changes.map((c) => _changeCard(c)),
          const SizedBox(height: 24),
          _recommendationsCard(),
          const SizedBox(height: 24),
          _ctaCard(context),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Summary delta card ─────────────────────────────────────────────────────

  Widget _summaryCard() {
    final delta = report.totalDelta;
    final isWorseOff = delta > 0;
    final isBetterOff = delta < 0;
    final color = isWorseOff
        ? EsepColors.expense
        : isBetterOff
            ? EsepColors.income
            : EsepColors.primary;
    final sign = delta > 0 ? '+' : '';
    final headline = isWorseOff
        ? 'Заплатите больше на'
        : isBetterOff
            ? 'Сэкономите'
            : 'Изменения нейтральны';
    final pctText = report.annualTax2025 > 0
        ? '${sign}${report.deltaPercent.toStringAsFixed(1)}%'
        : '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isWorseOff
                  ? Icons.trending_up
                  : isBetterOff
                      ? Icons.trending_down
                      : Icons.remove,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(headline,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: EsepColors.textSecondary)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${delta.abs() == 0 ? '' : (delta > 0 ? '+' : '-')}${_fmt.format(delta.abs())} ₸',
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: color, height: 1),
          ),
          if (pctText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(pctText,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ]),
        const SizedBox(height: 4),
        const Text('в год по сравнению с 2025',
            style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
        const SizedBox(height: 16),
        Container(height: 1, color: color.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _SmallStat(label: 'Было в 2025', value: '${_fmt.format(report.annualTax2025)} ₸')),
          Container(width: 1, height: 32, color: color.withValues(alpha: 0.15)),
          Expanded(child: _SmallStat(label: 'Будет в 2026', value: '${_fmt.format(report.annualTax2026)} ₸', valueColor: color)),
        ]),
      ]),
    );
  }

  // ── Profile chip ───────────────────────────────────────────────────────────

  Widget _profileChip() {
    final ans = report.answers;
    final parts = <String>[ans.entityType.label, 'на ${ans.regime.label}'];
    if (ans.hasEmployees) parts.add('${ans.employeesCount} сотр.');
    if (ans.isVatPayer) parts.add('плательщик НДС');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EsepColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Iconsax.profile_circle, size: 16, color: EsepColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: EsepColors.primary),
          ),
        ),
      ]),
    );
  }

  // ── Change cards ───────────────────────────────────────────────────────────

  Widget _changeCard(TaxChange c) {
    final color = switch (c.direction) {
      ChangeDirection.positive => EsepColors.income,
      ChangeDirection.negative => EsepColors.expense,
      ChangeDirection.neutral => EsepColors.primary,
    };
    final icon = _iconFor(c.iconName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EsepColors.textDisabled.withValues(alpha: 0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(c.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (c.annualDelta != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${c.annualDelta! > 0 ? '+' : ''}${_fmt.format(c.annualDelta!.abs())} ₸/год',
                      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(c.description,
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary, height: 1.4)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Recommendations ────────────────────────────────────────────────────────

  Widget _recommendationsCard() {
    if (report.recommendations.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EsepColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EsepColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Iconsax.lamp_on, color: EsepColors.gold, size: 18),
          SizedBox(width: 8),
          Text('Что делать',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: EsepColors.gold)),
        ]),
        const SizedBox(height: 10),
        ...report.recommendations.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ', style: TextStyle(color: EsepColors.gold, fontWeight: FontWeight.w800)),
                Expanded(
                  child: Text(r,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
              ]),
            )),
      ]),
    );
  }

  // ── CTA ─────────────────────────────────────────────────────────────────────

  Widget _ctaCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          EsepColors.primary,
          EsepColors.primaryDark,
        ]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Хотите пошаговый план?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 6),
        const Text(
          'Esep автоматически считает все изменения 2026, '
          'напоминает о дедлайнах, формирует 910 и счёт-фактуры.',
          style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Iconsax.flash_1, size: 18),
              label: const Text('Начать с Esep'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: EsepColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => context.go('/dashboard'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Скопировать отчёт',
            onPressed: () => _copyToClipboard(context),
            icon: const Icon(Iconsax.copy, color: Colors.white),
          ),
        ]),
      ]),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  IconData _iconFor(String name) {
    switch (name) {
      case 'mrp':         return Icons.monetization_on_outlined;
      case 'percent':     return Icons.percent;
      case 'group':       return Icons.group_outlined;
      case 'shield':      return Iconsax.shield_tick;
      case 'self':        return Iconsax.user_octagon;
      case 'vat':         return Iconsax.receipt_1;
      case 'opvr':        return Iconsax.wallet_money;
      case 'so':          return Icons.health_and_safety_outlined;
      case 'sn':          return Iconsax.briefcase;
      case 'progressive': return Iconsax.chart_2;
      default:            return Iconsax.info_circle;
    }
  }

  void _copyToClipboard(BuildContext context) {
    final ans = report.answers;
    final lines = <String>[
      '📊 Отчёт «Что изменилось в 2026» — Esep',
      '',
      'Профиль: ${ans.entityType.label} на ${ans.regime.label}'
          '${ans.hasEmployees ? " · ${ans.employeesCount} сотр." : ""}',
      'Годовой доход: ${_fmt.format(ans.annualRevenue)} ₸',
      '',
      'Налоги 2025: ${_fmt.format(report.annualTax2025)} ₸/год',
      'Налоги 2026: ${_fmt.format(report.annualTax2026)} ₸/год',
      'Дельта: ${report.totalDelta > 0 ? "+" : ""}${_fmt.format(report.totalDelta)} ₸/год',
      '',
      'Изменения:',
      ...report.changes.map((c) =>
          '• ${c.title}${c.annualDelta != null ? " (${c.annualDelta! > 0 ? "+" : ""}${_fmt.format(c.annualDelta!.abs())} ₸/год)" : ""}'),
      '',
      'esep.kz — попробуй бесплатно',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Отчёт скопирован в буфер')),
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor ?? EsepColors.textPrimary,
            )),
      ],
    );
  }
}
