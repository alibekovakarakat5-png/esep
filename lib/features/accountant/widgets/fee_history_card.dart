import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/accounting_client.dart';
import '../../../core/providers/accounting_provider.dart';

class FeeHistoryCard extends ConsumerStatefulWidget {
  const FeeHistoryCard({super.key, required this.clientId});
  final String clientId;
  @override
  ConsumerState<FeeHistoryCard> createState() => _FeeHistoryCardState();
}

class _FeeHistoryCardState extends ConsumerState<FeeHistoryCard> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;
  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(accountingProvider.notifier)
          .toggleFee(widget.clientId, month: _month);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Оплата не подтверждена: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref
        .watch(accountingProvider)
        .where((c) => c.id == widget.clientId)
        .firstOrNull;
    if (client == null) return const SizedBox.shrink();
    final history = [...client.feePayments]
      ..sort((a, b) => b.month.compareTo(a.month));
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('История гонораров',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (client.legacyFeeReceived)
                  const Text(
                      'Старая отметка оплаты сохранена без месяца. Она не включена в месячные итоги.'),
                Row(children: [
                  IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() =>
                              _month = DateTime(_month.year, _month.month - 1)),
                      icon: const Icon(Icons.chevron_left)),
                  Text(feeMonthKey(_month)),
                  IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() =>
                              _month = DateTime(_month.year, _month.month + 1)),
                      icon: const Icon(Icons.chevron_right)),
                ]),
                FilledButton(
                    onPressed: _busy ? null : _toggle,
                    child: Text(_busy
                        ? 'Сохранение…'
                        : client.feeReceivedFor(_month)
                            ? 'Отменить отметку за месяц'
                            : 'Отметить оплату за месяц')),
                const Text(
                    'Сумма фиксируется по гонорару при первой отметке месяца. Это отметка полной оплаты, не банковская сверка.'),
                if (history.isEmpty) const Text('Помесячных записей пока нет'),
                for (final payment in history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${payment.month} · ${payment.amount.toStringAsFixed(2)} ₸'),
                    subtitle: Text(payment.received
                        ? 'Оплата отмечена'
                        : 'Отметка отменена'),
                  ),
              ],
            )));
  }
}
