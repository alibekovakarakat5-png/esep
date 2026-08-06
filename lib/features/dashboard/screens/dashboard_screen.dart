import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../shared/widgets/adaptive_sheet.dart';
import '../../../shared/widgets/trial_banner.dart';
import '../../../core/services/file_saver.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/kz_tax_constants.dart';
import '../../../core/models/transaction.dart' as model;
import '../../../core/providers/transaction_provider.dart';
import '../../../core/providers/invoice_provider.dart';
import '../../../core/providers/demo_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/excel_export_service.dart';
import '../../../core/providers/client_provider.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/providers/feature_tour_provider.dart';
import '../../../shared/widgets/beta_feedback_button.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,##0', 'ru_RU');

    final monthIncome    = ref.watch(monthIncomeProvider);
    final monthlyData    = ref.watch(monthlyChartProvider);
    final halfYearIncome = ref.watch(halfYearIncomeProvider);
    final regimeLimit    = KzTax.simplified910HalfYearLimit;
    final usedPercent    = regimeLimit > 0 ? halfYearIncome / regimeLimit : 0.0;
    final social         = KzTax.calculateMonthlySocial();
    final unpaidCount    = ref.watch(unpaidInvoicesProvider).length;
    final unpaidTotal    = ref.watch(totalUnpaidProvider);
    final transactions   = ref.watch(transactionProvider);
    final recentTxs      = transactions.take(5).toList();
    final isLoading      = ref.watch(transactionLoadingProvider) || ref.watch(invoiceLoadingProvider);
    final socialDays     = _daysUntilSocialPayment();
    final deadlineInfo   = _nextDeadline();
    final invoicesTotal  = ref.watch(invoiceProvider).length;
    final tax910         = halfYearIncome * KzTax.simplified910TotalRate;

    // ── Вариант В: главная — список дел, а не витрина цифр ──────────────
    // Задачи собираются из сигналов, которые уже считаются в коде
    // (раньше они были разбросаны по баннерам).
    final tasks = <_TaskData>[];
    final doneItems = <_TaskData>[];

    if (transactions.isEmpty) {
      tasks.add(const _TaskData(
        mark: '1',
        color: EsepColors.primary,
        title: 'Загрузите выписку из банка',
        subtitle: 'Esep разнесёт операции и посчитает налог за 10 секунд',
        route: '/bank-connect',
      ));
    } else {
      doneItems.add(_TaskData(
        mark: '✓',
        color: EsepColors.income,
        title: 'Операции загружены',
        subtitle: '${transactions.length} ${_opsWord(transactions.length)} в учёте',
      ));
    }

    if (halfYearIncome > 0) {
      if (deadlineInfo.daysLeft <= 60) {
        tasks.add(_TaskData(
          mark: '!',
          color: EsepColors.warning,
          title: 'Сдать форму 910 до ${deadlineInfo.label}',
          subtitle: 'Налог ${fmt.format(tax910)} ₸ посчитан. Осталось сформировать и отправить',
          route: '/form-910',
        ));
      } else {
        doneItems.add(_TaskData(
          mark: '✓',
          color: EsepColors.income,
          title: 'Налог посчитан — ${fmt.format(tax910)} ₸',
          subtitle: 'Упрощёнка 4% с дохода ${fmt.format(halfYearIncome)} ₸',
        ));
      }
    }

    if (socialDays <= 7) {
      tasks.add(_TaskData(
        mark: '₸',
        color: EsepColors.expense,
        title: socialDays == 0
            ? 'Оплатить взносы сегодня — ${fmt.format(social.total)} ₸'
            : 'Оплатить взносы до 25-го — ${fmt.format(social.total)} ₸',
        subtitle: socialDays == 0
            ? 'ОПВ, СО и медстрахование за месяц'
            : 'ОПВ, СО и медстрахование · осталось $socialDays ${_daysWord(socialDays)}',
        route: '/taxes',
      ));
    }

    if (unpaidCount > 0) {
      tasks.add(_TaskData(
        mark: '$unpaidCount',
        color: EsepColors.expense,
        title: unpaidCount == 1
            ? 'Один счёт не оплачен'
            : '$unpaidCount ${_invoiceWord(unpaidCount)}',
        subtitle: 'Вам должны ${fmt.format(unpaidTotal)} ₸. Напомнить в WhatsApp — в один тап',
        route: '/debtors',
      ));
    } else if (invoicesTotal > 0) {
      doneItems.add(const _TaskData(
        mark: '✓',
        color: EsepColors.income,
        title: 'Все счета оплачены',
        subtitle: 'Дебиторской задолженности нет',
      ));
    }

    if (usedPercent > 0.8) {
      tasks.add(_TaskData(
        mark: '!',
        color: EsepColors.expense,
        title: usedPercent >= 1
            ? 'Лимит упрощёнки превышен'
            : 'Лимит упрощёнки почти исчерпан',
        subtitle: 'Использовано ${(usedPercent * 100).toStringAsFixed(1)}% лимита · что делать дальше',
        route: '/regime-guide',
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Esep'),
        actions: [
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else ...[
            IconButton(
              icon: const Icon(Iconsax.document_download),
              tooltip: 'Отчёт: PDF / Excel',
              onPressed: () => _exportReport(context, ref),
            ),
            IconButton(
              icon: const Icon(Iconsax.setting_2),
              tooltip: 'Настройки',
              onPressed: () => context.go('/settings'),
            ),
          ],
          const BetaFeedbackButton(screen: 'dashboard', compact: true),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        return ListView(
        padding: EdgeInsets.all(wide ? 24 : 16),
        children: [

          // ── Trial countdown / paywall banner ───────────────────────
          const TrialBanner(),

          // ── Demo banner ────────────────────────────────────────────
          if (ref.watch(isDemoProvider)) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: EsepColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EsepColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Iconsax.info_circle, color: EsepColors.warning, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Демо-режим — данные не сохраняются',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: EsepColors.warning),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    ref.read(authProvider.notifier).logout();
                    context.go('/auth');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: EsepColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Войти', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ── Feature Tour ───────────────────────────────────────
          if (ref.watch(featureTourProvider).showDashboardTour)
            _FeatureTourBanner(
              step: ref.watch(featureTourProvider).dashboardStep,
              onNext: () => ref.read(featureTourProvider.notifier).nextStep(),
              onDismiss: () => ref.read(featureTourProvider.notifier).dismiss(),
            ),
          if (ref.watch(featureTourProvider).showDashboardTour)
            const SizedBox(height: 10),

          // ── Диагностика «Что изменилось в 2026» ────────────────
          if (ref.watch(diagnosisBannerVisibleProvider)) ...[
            _DiagnosisBanner(
              onTap: () => context.go('/diagnosis'),
              onDismiss: () => hideDiagnosisBanner(ref),
            ),
            const SizedBox(height: 12),
          ],

          // ── Заголовок: сколько осталось сделать ────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tasksTitle(tasks.length),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      letterSpacing: -0.4, color: EsepColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                tasks.isEmpty
                    ? 'Esep следит за сроками — новых требований нет'
                    : 'Остальное Esep сделал сам',
                style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary),
              ),
            ]),
          ),

          // ── Задачи ─────────────────────────────────────────────────
          ...tasks.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _TaskCard(data: t),
              )),

          // ── Сделано ────────────────────────────────────────────────
          if (doneItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 9),
              child: Text('СДЕЛАНО',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600,
                      letterSpacing: 0.8, color: EsepColors.textDisabled)),
            ),
            ...doneItems.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _TaskCard(data: t, done: true),
                )),
          ],

          // ── Три компактные метрики ─────────────────────────────────
          const SizedBox(height: 12),
          _TriStats(
            monthIncome: monthIncome,
            halfYearTax: tax910,
            usedPercent: usedPercent,
            onIncomeTap: () => context.go('/transactions'),
            onTaxTap: () => context.go('/form-910'),
          ),

          // Последние операции
          if (recentTxs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(
                child: Text('Последние операции',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: EsepColors.textPrimary)),
              ),
              TextButton(
                onPressed: () => context.go('/transactions'),
                child: const Text('Все', style: TextStyle(fontSize: 13, color: EsepColors.primary)),
              ),
            ]),
            const SizedBox(height: 4),
            Card(
              child: Column(
                children: recentTxs.asMap().entries.map((e) {
                  final i   = e.key;
                  final tx  = e.value;
                  final color = tx.isIncome ? EsepColors.income : EsepColors.expense;
                  return Column(children: [
                    ListTile(
                      dense: true,
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(tx.isIncome ? Iconsax.arrow_circle_up : Iconsax.arrow_circle_down, color: color, size: 18),
                      ),
                      title: Text(tx.title,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(DateFormat('dd MMM', 'ru_RU').format(tx.date),
                          style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
                      trailing: Text(
                        '${tx.isIncome ? "+" : "−"} ${fmt.format(tx.amount)} ₸',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
                    if (i < recentTxs.length - 1)
                      const Divider(height: 1, indent: 56, endIndent: 16),
                  ]);
                }).toList(),
              ),
            ),
          ],

          // ── График доходов и расходов ──────────────────────────────
          const SizedBox(height: 20),
          const Text('Доходы и расходы за 6 месяцев',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: EsepColors.textPrimary)),
          const SizedBox(height: 8),
          _MonthlyChart(data: monthlyData),

          const SizedBox(height: 32),
        ],
      );
      },
      ),
    );
  }

  static void _exportReport(BuildContext context, WidgetRef ref) {
    final txs = ref.read(transactionProvider);
    if (txs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет транзакций для отчёта')),
      );
      return;
    }

    showAdaptiveSheet(
      context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: EsepColors.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Финансовый отчёт',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Выберите действие',
                style: TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _ReportAction(
                icon: Iconsax.printer,
                label: 'Печать / PDF',
                color: EsepColors.primary,
                onTap: () async {
                  Navigator.pop(ctx);
                  final doc = await _buildReport(txs);
                  await Printing.layoutPdf(onLayout: (_) => doc.save());
                },
              )),
              const SizedBox(width: 12),
              Expanded(child: _ReportAction(
                icon: Iconsax.share,
                label: 'Поделиться',
                color: EsepColors.info,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareReport(context, txs);
                },
              )),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _ReportAction(
                icon: Iconsax.document_download,
                label: 'Экспорт в Excel',
                color: const Color(0xFF217346),
                onTap: () {
                  Navigator.pop(ctx);
                  final invoices = ref.read(invoiceProvider);
                  final clients = ref.read(clientProvider);
                  final company = ref.read(companyProvider);
                  ExcelExportService.exportFullReport(
                    transactions: txs,
                    invoices: invoices,
                    clients: clients,
                    companyName: company.name,
                    companyIin: company.iin,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  static Future<pw.Document> _buildReport(List<model.Transaction> txs) async {
    final now = DateTime.now();
    final period = DateFormat('LLLL yyyy', 'ru_RU').format(now);
    return PdfService.generateReport(
      transactions: txs,
      period: period[0].toUpperCase() + period.substring(1),
    );
  }

  static Future<void> _shareReport(BuildContext context, List<model.Transaction> txs) async {
    try {
      final doc = await _buildReport(txs);
      final bytes = await doc.save();
      final now = DateTime.now();
      final fileName = 'esep_report_${DateFormat('yyyy_MM').format(now)}.pdf';

      await saveAndShareFile(bytes, fileName, subject: 'Финансовый отчёт — Esep');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: EsepColors.expense),
        );
      }
    }
  }

  /// Заголовок списка дел: «Всё сделано» / «Одна задача…» / «N задач…»
  static String _tasksTitle(int n) {
    switch (n) {
      case 0:
        return 'Всё сделано';
      case 1:
        return 'Одна задача на этой неделе';
      case 2:
        return 'Две задачи на этой неделе';
      case 3:
        return 'Три задачи на этой неделе';
      case 4:
        return 'Четыре задачи на этой неделе';
      default:
        return '$n задач на этой неделе';
    }
  }

  static String _opsWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'операция';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'операции';
    return 'операций';
  }

  static _DeadlineInfo _nextDeadline() {
    final now = DateTime.now();
    DateTime next;
    String label;
    if (now.month < 8 || (now.month == 8 && now.day <= 15)) {
      next  = DateTime(now.year, 8, 15);
      label = '15 авг ${now.year}';
    } else {
      final year = now.month > 8 ? now.year + 1 : now.year;
      next  = DateTime(year, 2, 15);
      label = '15 фев $year';
    }
    return _DeadlineInfo(label: label, daysLeft: next.difference(now).inDays);
  }

  static int _daysUntilSocialPayment() {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, 25);
    if (now.day > 25) d = DateTime(now.year, now.month + 1, 25);
    return d.difference(now).inDays;
  }

  static String _daysWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'дня';
    return 'дней';
  }

  static String _invoiceWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'неоплаченный счёт';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'неоплаченных счёта';
    return 'неоплаченных счетов';
  }
}

class _DeadlineInfo {
  final String label;
  final int daysLeft;
  const _DeadlineInfo({required this.label, required this.daysLeft});
}

// ── Report Action Button ─────────────────────────────────────────────────────
class _ReportAction extends StatelessWidget {
  const _ReportAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

// ── Задача «что нужно сделать» (вариант В главной) ──────────────────────────
class _TaskData {
  final String mark;
  final Color color;
  final String title;
  final String subtitle;
  final String? route;
  const _TaskData({
    required this.mark,
    required this.color,
    required this.title,
    required this.subtitle,
    this.route,
  });
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.data, this.done = false});
  final _TaskData data;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: data.color,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Text(data.mark,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data.title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: EsepColors.textPrimary,
                      height: 1.3)),
              const SizedBox(height: 3),
              Text(data.subtitle,
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: EsepColors.textSecondary,
                      height: 1.4)),
            ]),
          ),
          if (!done && data.route != null) ...[
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(Iconsax.arrow_right_3,
                  size: 16, color: EsepColors.textDisabled),
            ),
          ],
        ]),
      ),
    );

    if (done) return Opacity(opacity: 0.62, child: card);
    if (data.route == null) return card;
    return GestureDetector(onTap: () => context.go(data.route!), child: card);
  }
}

// ── Три компактные метрики: Доход / Налог / Лимит ───────────────────────────
class _TriStats extends StatelessWidget {
  const _TriStats({
    required this.monthIncome,
    required this.halfYearTax,
    required this.usedPercent,
    required this.onIncomeTap,
    required this.onTaxTap,
  });
  final double monthIncome;
  final double halfYearTax;
  final double usedPercent;
  final VoidCallback onIncomeTap;
  final VoidCallback onTaxTap;

  @override
  Widget build(BuildContext context) {
    final compact = NumberFormat.compact(locale: 'ru_RU');

    Widget cell(String label, String value, Color valueColor, VoidCallback? onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: EsepColors.textSecondary)),
                const SizedBox(height: 3),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: valueColor)),
              ]),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      cell('Доход / мес', compact.format(monthIncome), EsepColors.income, onIncomeTap),
      const SizedBox(width: 8),
      cell('Налог 910', compact.format(halfYearTax), EsepColors.textPrimary, onTaxTap),
      const SizedBox(width: 8),
      cell(
        'Лимит',
        '${(usedPercent * 100).toStringAsFixed(1)}%',
        usedPercent > 0.8 ? EsepColors.expense : EsepColors.textPrimary,
        null,
      ),
    ]);
  }
}

// ── Monthly Chart ────────────────────────────────────────────────────────────
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.data});
  final List<MonthlyData> data;

  @override
  Widget build(BuildContext context) {
    final maxVal = data.fold(0.0, (m, d) => [m, d.income, d.expense].reduce((a, b) => a > b ? a : b));
    final fmt = NumberFormat.compact(locale: 'ru_RU');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            _Legend(color: EsepColors.income, label: 'Доход'),
            SizedBox(width: 16),
            _Legend(color: EsepColors.expense, label: 'Расход'),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: BarChart(BarChartData(
              maxY: maxVal == 0 ? 100 : maxVal * 1.2,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: EsepColors.divider, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 40,
                  getTitlesWidget: (v, _) => Text(fmt.format(v),
                      style: const TextStyle(fontSize: 9, color: EsepColors.textDisabled)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= data.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(data[i].label,
                          style: const TextStyle(fontSize: 10, color: EsepColors.textSecondary)),
                    );
                  },
                )),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: List.generate(data.length, (i) {
                final d = data[i];
                return BarChartGroupData(x: i, barsSpace: 3, barRods: [
                  BarChartRodData(toY: d.income, color: EsepColors.income, width: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  BarChartRodData(toY: d.expense, color: EsepColors.expense, width: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ]);
              }),
            )),
          ),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
  ]);
}

// ── Feature Tour Banner ─────────────────────────────────────────────────────
class _FeatureTourBanner extends StatelessWidget {
  const _FeatureTourBanner({required this.step, required this.onNext, required this.onDismiss});
  final int step;
  final VoidCallback onNext;
  final VoidCallback onDismiss;

  static const _tips = [
    _TourTip(
      icon: Iconsax.arrow_circle_up,
      title: 'Записывайте доходы',
      body: 'Добавляйте операции кнопкой «+» на вкладке «Деньги». Esep сам посчитает ваш налог.',
      color: EsepColors.income,
    ),
    _TourTip(
      icon: Iconsax.link_21,
      title: 'Или загрузите выписку',
      body: 'Скачайте выписку из Kaspi или другого банка — всё добавится автоматически.',
      color: Color(0xFFF14635),
    ),
    _TourTip(
      icon: Iconsax.calculator,
      title: 'Налоги считаются сами',
      body: 'Esep покажет сколько денег отложить и когда заплатить. Без бухгалтера.',
      color: Color(0xFF7B2FBE),
    ),
    _TourTip(
      icon: Iconsax.notification,
      title: 'Напомним заранее',
      body: 'За 7 и 3 дня до каждого платежа придёт уведомление. Штрафов не будет.',
      color: EsepColors.warning,
    ),
    _TourTip(
      icon: Iconsax.document_download,
      title: 'Отчёт — одной кнопкой',
      body: 'Когда придёт время — иконка отчёта вверху главной соберёт PDF или Excel.',
      color: EsepColors.primary,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (step >= _tips.length) {
      // Auto-dismiss when all tips shown
      WidgetsBinding.instance.addPostFrameCallback((_) => onDismiss());
      return const SizedBox.shrink();
    }

    final tip = _tips[step];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tip.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tip.color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: tip.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(tip.icon, color: tip.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(tip.title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tip.color))),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Iconsax.close_circle, size: 20, color: EsepColors.textDisabled),
          ),
        ]),
        const SizedBox(height: 8),
        Text(tip.body, style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary, height: 1.4)),
        const SizedBox(height: 10),
        Row(children: [
          // Step indicator
          ...List.generate(_tips.length, (i) => Container(
            width: i == step ? 16 : 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: i == step ? tip.color : EsepColors.divider,
              borderRadius: BorderRadius.circular(3),
            ),
          )),
          const Spacer(),
          TextButton(
            onPressed: step < _tips.length - 1 ? onNext : onDismiss,
            child: Text(
              step < _tips.length - 1 ? 'Далее' : 'Понятно',
              style: TextStyle(color: tip.color, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _TourTip {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  const _TourTip({required this.icon, required this.title, required this.body, required this.color});
}

/// Промо-баннер для онбординг-диагностики «Что изменилось в 2026».
/// Показывается всем — это лид-магнит и upsell-крючок.
/// Показан ли ещё баннер диагностики. Раньше он висел на дашборде вечно —
/// даже у тех, кто диагностику уже прошёл. Закрывается крестиком навсегда.
final diagnosisBannerVisibleProvider = StateProvider<bool>((ref) {
  return !(Hive.box('settings')
      .get('diagnosis_banner_hidden', defaultValue: false) as bool);
});

void hideDiagnosisBanner(WidgetRef ref) {
  Hive.box('settings').put('diagnosis_banner_hidden', true);
  ref.read(diagnosisBannerVisibleProvider.notifier).state = false;
}

class _DiagnosisBanner extends StatelessWidget {
  const _DiagnosisBanner({required this.onTap, required this.onDismiss});
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0099CC), Color(0xFF0077A8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Iconsax.chart_2, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Что изменилось для вас в 2026',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              SizedBox(height: 2),
              Text('1 минута — узнайте сколько заплатите по новому НК',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Начать',
                  style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
              SizedBox(width: 4),
              Icon(Iconsax.arrow_right_3, color: Colors.white, size: 14),
            ]),
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Iconsax.close_circle, color: Colors.white70, size: 18),
            tooltip: 'Больше не показывать',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ]),
      ),
    );
  }
}
