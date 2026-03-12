import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/accounting_client.dart';
import '../../../core/providers/accounting_provider.dart';
import 'add_accounting_client_screen.dart';

// ── Filter enum ───────────────────────────────────────────────────────────────

enum _Filter { all, urgent, docs, fee }

extension _FilterExt on _Filter {
  String get label => switch (this) {
        _Filter.all    => 'Все',
        _Filter.urgent => 'Срочные',
        _Filter.docs   => 'Ждут документы',
        _Filter.fee    => 'Должники',
      };
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AccountantDashboardScreen extends ConsumerStatefulWidget {
  const AccountantDashboardScreen({super.key});

  @override
  ConsumerState<AccountantDashboardScreen> createState() =>
      _AccountantDashboardScreenState();
}

class _AccountantDashboardScreenState
    extends ConsumerState<AccountantDashboardScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final clients     = ref.watch(accountingProvider);
    final urgentCount = ref.watch(urgentCountProvider);
    final awaitDocs   = ref.watch(awaitingDocsCountProvider);
    final fee         = ref.watch(totalFeeProvider);
    final fmt         = NumberFormat('#,##0', 'ru_RU');

    final filtered = _applyFilter(clients, _filter);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Бухгалтерия'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.calendar_1),
            tooltip: 'Дедлайны',
            onPressed: () => context.go('/accountant/calendar'),
          ),
          IconButton(
            icon: const Icon(Iconsax.add_circle),
            tooltip: 'Добавить клиента',
            onPressed: () => _addClient(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Summary row ──────────────────────────────────────────────────
          Row(children: [
            _SummaryChip(
              icon: Iconsax.people,
              label: '${clients.length} клиентов',
              color: EsepColors.primary,
            ),
            const SizedBox(width: 8),
            _SummaryChip(
              icon: Iconsax.danger,
              label: '$urgentCount срочных',
              color: urgentCount > 0 ? EsepColors.expense : EsepColors.textSecondary,
            ),
            const SizedBox(width: 8),
            _SummaryChip(
              icon: Iconsax.document_text,
              label: '$awaitDocs ждут',
              color: awaitDocs > 0 ? EsepColors.warning : EsepColors.textSecondary,
            ),
          ]),

          // ── My fee summary ───────────────────────────────────────────────
          const SizedBox(height: 12),
          _FeeBanner(received: fee.received, total: fee.total, fmt: fmt),

          // ── Upcoming deadlines strip ─────────────────────────────────────
          const SizedBox(height: 16),
          _UpcomingStrip(),

          // ── Filter chips ─────────────────────────────────────────────────
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _Filter.values.map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  selectedColor: EsepColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: EsepColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: _filter == f ? EsepColors.primary : EsepColors.textSecondary,
                    fontWeight: _filter == f ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              )).toList(),
            ),
          ),

          // ── Client list ──────────────────────────────────────────────────
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  _filter == _Filter.all
                      ? 'Нет клиентов.\nНажмите + чтобы добавить.'
                      : 'Нет клиентов в этой категории',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: EsepColors.textSecondary, fontSize: 14),
                ),
              ),
            )
          else
            ...filtered.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ClientCard(
                    client: c,
                    onTap: () => context.push('/accountant/client/${c.id}'),
                  ),
                )),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<AccountingClient> _applyFilter(List<AccountingClient> all, _Filter f) {
    return switch (f) {
      _Filter.all    => all,
      _Filter.urgent => all.where((c) {
          final d = nearestDeadline(c);
          return d != null && d.daysLeft <= 3;
        }).toList(),
      _Filter.docs   => all.where((c) => c.missingDocs > 0).toList(),
      _Filter.fee    => all.where((c) => !c.feeReceivedThisMonth && c.monthlyFee > 0).toList(),
    };
  }

  void _addClient(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddAccountingClientScreen()),
    );
  }
}

// ── Summary Chip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    ),
  );
}

// ── Fee Banner ────────────────────────────────────────────────────────────────

class _FeeBanner extends StatelessWidget {
  const _FeeBanner({required this.received, required this.total, required this.fmt});
  final double received, total;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final pending = total - received;
    final allPaid = pending <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EsepColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EsepColors.divider),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: EsepColors.income.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Iconsax.wallet_money, color: EsepColors.income, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Мой гонорар за месяц',
                style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
            const SizedBox(height: 2),
            Text('${fmt.format(received)} ₸ из ${fmt.format(total)} ₸',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: EsepColors.textPrimary)),
          ]),
        ),
        if (!allPaid)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: EsepColors.expense.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('−${fmt.format(pending)} ₸',
                style: const TextStyle(fontSize: 12, color: EsepColors.expense,
                    fontWeight: FontWeight.w600)),
          )
        else
          const Icon(Iconsax.tick_circle, color: EsepColors.income, size: 22),
      ]),
    );
  }
}

// ── Upcoming Deadlines Strip ──────────────────────────────────────────────────

class _UpcomingStrip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadlines = ref.watch(allUpcomingDeadlinesProvider);
    // Group by date, show next 3 distinct dates
    final grouped = <String, List<ClientDeadline>>{};
    for (final d in deadlines.where((d) => !d.isPast)) {
      final key = DateFormat('dd MMM', 'ru_RU').format(d.date);
      grouped.putIfAbsent(key, () => []).add(d);
      if (grouped.length >= 3) break;
    }
    if (grouped.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Ближайшие дедлайны',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: EsepColors.textSecondary)),
      const SizedBox(height: 8),
      ...grouped.entries.map((e) {
        final date = e.key;
        final items = e.value;
        final firstD = items.first;
        final color = firstD.isUrgent
            ? EsepColors.expense
            : firstD.isWarning
                ? EsepColors.warning
                : EsepColors.primary;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text('$date — ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            Expanded(
              child: Text(
                items.length == 1
                    ? '${items.first.label} (${items.first.clientName})'
                    : '${items.first.label} (${items.length} клиентов)',
                style: const TextStyle(fontSize: 13, color: EsepColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        );
      }),
    ]);
  }
}

// ── Client Card ───────────────────────────────────────────────────────────────

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onTap});
  final AccountingClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deadline = nearestDeadline(client);
    final status   = _clientStatus(client, deadline);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EsepColors.cardLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: status.borderColor),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header row ─────────────────────────────────────────────────
          Row(children: [
            // Status dot
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(client.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: EsepColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            // Entity type badge
            _Badge(label: client.entityType.label,
                color: client.entityType == ClientEntityType.ip
                    ? EsepColors.primary
                    : const Color(0xFF7B2FBE)),
            const SizedBox(width: 6),
            // Regime badge
            _Badge(label: client.regime.label, color: EsepColors.textSecondary),
          ]),

          const SizedBox(height: 10),

          // ── Deadline row ────────────────────────────────────────────────
          if (deadline != null)
            _InfoRow(
              icon: Iconsax.calendar_1,
              iconColor: deadline.isUrgent
                  ? EsepColors.expense
                  : deadline.isWarning
                      ? EsepColors.warning
                      : EsepColors.textSecondary,
              text: deadline.label,
              trailing: _DaysChip(daysLeft: deadline.daysLeft),
            )
          else
            const _InfoRow(
              icon: Iconsax.tick_circle,
              iconColor: EsepColors.income,
              text: 'Нет дедлайнов в ближайшие 3 месяца',
            ),

          const SizedBox(height: 6),

          // ── Docs row ────────────────────────────────────────────────────
          _InfoRow(
            icon: client.allDocsReceived ? Iconsax.tick_circle : Iconsax.document_text,
            iconColor: client.allDocsReceived ? EsepColors.income : EsepColors.warning,
            text: client.allDocsReceived
                ? 'Все документы получены'
                : '${client.missingDocs} ${_docWord(client.missingDocs)} не получено',
          ),

          const SizedBox(height: 6),

          // ── Fee row ─────────────────────────────────────────────────────
          if (client.monthlyFee > 0)
            _InfoRow(
              icon: client.feeReceivedThisMonth
                  ? Iconsax.wallet_money
                  : Iconsax.money_recive,
              iconColor: client.feeReceivedThisMonth
                  ? EsepColors.income
                  : EsepColors.expense,
              text: client.feeReceivedThisMonth
                  ? 'Гонорар получен'
                  : 'Гонорар не оплачен — ${NumberFormat('#,##0', 'ru_RU').format(client.monthlyFee)} ₸',
            ),
        ]),
      ),
    );
  }

  _ClientStatus _clientStatus(AccountingClient c, ClientDeadline? d) {
    if (d != null && d.daysLeft <= 3) {
      return _ClientStatus(
          color: EsepColors.expense,
          borderColor: EsepColors.expense.withValues(alpha: 0.35));
    }
    if ((d != null && d.daysLeft <= 7) || c.missingDocs > 0) {
      return _ClientStatus(
          color: EsepColors.warning,
          borderColor: EsepColors.warning.withValues(alpha: 0.35));
    }
    return const _ClientStatus(
        color: EsepColors.income, borderColor: EsepColors.divider);
  }

  String _docWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'документ';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'документа';
    return 'документов';
  }
}

class _ClientStatus {
  final Color color;
  final Color borderColor;
  const _ClientStatus({required this.color, required this.borderColor});
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.trailing,
  });
  final IconData icon;
  final Color iconColor;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: iconColor),
    const SizedBox(width: 6),
    Expanded(
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            overflow: TextOverflow.ellipsis)),
    if (trailing != null) trailing!,
  ]);
}

class _DaysChip extends StatelessWidget {
  const _DaysChip({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final color = daysLeft <= 3
        ? EsepColors.expense
        : daysLeft <= 7
            ? EsepColors.warning
            : EsepColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        daysLeft == 0 ? 'сегодня' : '$daysLeft дн',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
