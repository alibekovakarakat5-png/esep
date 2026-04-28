import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class _Payment {
  final String id;
  final String kbk;
  final String? kbkLabel;
  final String? taxPeriod;
  final num paidAmount;
  final String paidAt;
  final String? bank;
  final String? paymentDoc;
  final String actualStatus;  // pending_check / posted / misposted / missing
  final String? mispostKbk;
  final int daysSincePaid;
  final String? note;

  const _Payment({
    required this.id,
    required this.kbk,
    required this.kbkLabel,
    required this.taxPeriod,
    required this.paidAmount,
    required this.paidAt,
    required this.bank,
    required this.paymentDoc,
    required this.actualStatus,
    required this.mispostKbk,
    required this.daysSincePaid,
    required this.note,
  });

  factory _Payment.fromJson(Map<String, dynamic> j) => _Payment(
        id: j['id'].toString(),
        kbk: (j['kbk'] ?? '') as String,
        kbkLabel: j['kbk_label'] as String?,
        taxPeriod: j['tax_period'] as String?,
        paidAmount: (j['paid_amount'] is num)
            ? j['paid_amount'] as num
            : num.tryParse(j['paid_amount']?.toString() ?? '0') ?? 0,
        paidAt: (j['paid_at'] ?? '').toString().split('T').first,
        bank: j['bank'] as String?,
        paymentDoc: j['payment_doc'] as String?,
        actualStatus: (j['actual_status'] ?? 'pending_check') as String,
        mispostKbk: j['mispost_kbk'] as String?,
        daysSincePaid: (j['days_since_paid'] is int)
            ? j['days_since_paid'] as int
            : int.tryParse(j['days_since_paid']?.toString() ?? '0') ?? 0,
        note: j['note'] as String?,
      );

  bool get isPending => actualStatus == 'pending_check';
  bool get isPosted  => actualStatus == 'posted';
  bool get isMispost => actualStatus == 'misposted';
  bool get isMissing => actualStatus == 'missing';
  bool get isProblem => isMispost || isMissing;

  ({Color color, String text}) statusVisual() {
    if (isPosted)  return (color: const Color(0xFF1F7A3F), text: 'Разнесено');
    if (isMispost) return (color: EsepColors.expense, text: 'Не на тот код');
    if (isMissing) return (color: EsepColors.expense, text: 'Не разнесено');
    if (daysSincePaid >= 30) return (color: EsepColors.expense, text: 'Долго висит');
    if (daysSincePaid >= 14) return (color: EsepColors.warning, text: 'Пора проверить');
    return (color: EsepColors.textSecondary, text: 'В ожидании');
  }
}

class _Alert {
  final String id;
  final String level;       // 'red' | 'yellow' | 'info'
  final String title;
  final String action;
  final num paidAmount;
  final String paidAt;
  final String kbk;

  const _Alert({
    required this.id, required this.level, required this.title,
    required this.action, required this.paidAmount, required this.paidAt,
    required this.kbk,
  });

  factory _Alert.fromJson(Map<String, dynamic> j) => _Alert(
        id: j['id'].toString(),
        level: (j['level'] ?? 'info') as String,
        title: (j['alert_title'] ?? '') as String,
        action: (j['alert_action'] ?? '') as String,
        paidAmount: (j['paid_amount'] is num)
            ? j['paid_amount'] as num
            : num.tryParse(j['paid_amount']?.toString() ?? '0') ?? 0,
        paidAt: (j['paid_at'] ?? '').toString().split('T').first,
        kbk: (j['kbk'] ?? '') as String,
      );
}

// ── Providers ────────────────────────────────────────────────────────────────

final _paymentsProvider = FutureProvider.autoDispose<List<_Payment>>((ref) async {
  final list = await ApiClient.get('/account/payments') as List;
  return list.map((j) => _Payment.fromJson(j as Map<String, dynamic>)).toList();
});

final _alertsProvider = FutureProvider.autoDispose<List<_Alert>>((ref) async {
  final list = await ApiClient.get('/account/alerts') as List;
  return list.map((j) => _Alert.fromJson(j as Map<String, dynamic>)).toList();
});

// ── Screen ───────────────────────────────────────────────────────────────────

class AccountMonitorScreen extends ConsumerWidget {
  const AccountMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(_paymentsProvider);
    final alerts   = ref.watch(_alertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Лицевой счёт'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.info_circle),
            tooltip: 'Зачем это нужно',
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Iconsax.add),
        label: const Text('Добавить платёж'),
        onPressed: () => _addDialog(context, ref),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_paymentsProvider);
          ref.invalidate(_alertsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            // Алерты сверху
            alerts.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : Column(children: list.map((a) => _AlertCard(alert: a)).toList()),
            ),

            const SizedBox(height: 8),

            // Список всех платежей
            payments.when(
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(24), child: CircularProgressIndicator(),
              )),
              error: (e, _) => _ErrorView(message: e.toString(),
                  onRetry: () => ref.invalidate(_paymentsProvider)),
              data: (list) => list.isEmpty
                  ? _EmptyState(onAdd: () => _addDialog(context, ref))
                  : Column(
                      children: list.map((p) => _PaymentTile(
                        payment: p,
                        onChange: () {
                          ref.invalidate(_paymentsProvider);
                          ref.invalidate(_alertsProvider);
                        },
                      )).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HelpSheet(),
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final amountCtrl = TextEditingController();
    final docCtrl    = TextEditingController();
    final periodCtrl = TextEditingController(text: _currentPeriod());
    String kbk = '101101'; // ИПН по 910 (по умолчанию)
    DateTime paidAt = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Платёж в налоговую'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: kbk,
                  decoration: const InputDecoration(
                    labelText: 'КБК (вид налога)', border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: '101101', child: Text('101101 — ИПН по форме 910')),
                    DropdownMenuItem(value: '101110', child: Text('101110 — КПН (крупный бизнес)')),
                    DropdownMenuItem(value: '101111', child: Text('101111 — КПН (средний бизнес)')),
                    DropdownMenuItem(value: '105101', child: Text('105101 — НДС')),
                    DropdownMenuItem(value: '101201', child: Text('101201 — ИПН с зарплаты')),
                    DropdownMenuItem(value: '103101', child: Text('103101 — Социальный налог')),
                    DropdownMenuItem(value: '104301', child: Text('104301 — ОПВ')),
                    DropdownMenuItem(value: '104302', child: Text('104302 — ОПВР')),
                    DropdownMenuItem(value: '104101', child: Text('104101 — СО (соц.отчисления)')),
                    DropdownMenuItem(value: '104406', child: Text('104406 — ВОСМС работника')),
                    DropdownMenuItem(value: '104407', child: Text('104407 — ООСМС работодателя')),
                  ],
                  onChanged: (v) => setS(() => kbk = v ?? kbk),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(
                    labelText: 'Сумма ₸', border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        initialDate: paidAt,
                      );
                      if (picked != null) setS(() => paidAt = picked);
                    },
                    child: AbsorbPointer(
                      child: TextField(
                        controller: TextEditingController(text: _fmt(paidAt)),
                        decoration: const InputDecoration(
                          labelText: 'Дата оплаты', border: OutlineInputBorder(),
                          suffixIcon: Icon(Iconsax.calendar_1, size: 16),
                        ),
                      ),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: periodCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Период (2026-H1)', border: OutlineInputBorder(),
                    ),
                  )),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: docCtrl,
                  decoration: const InputDecoration(
                    labelText: '№ платёжки (опционально)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: amountCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        );
      }),
    );

    if (ok == true) {
      try {
        final amount = double.tryParse(
          amountCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.'),
        ) ?? 0;
        if (amount <= 0) throw Exception('Сумма должна быть > 0');
        await ApiClient.post('/account/payments', {
          'kbk': kbk,
          'kbk_label': _kbkLabel(kbk),
          'paid_amount': amount,
          'paid_at': _fmt(paidAt),
          'tax_period': periodCtrl.text.trim().isEmpty ? null : periodCtrl.text.trim(),
          'payment_doc': docCtrl.text.trim().isEmpty ? null : docCtrl.text.trim(),
        });
        ref.invalidate(_paymentsProvider);
        ref.invalidate(_alertsProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }
}

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _currentPeriod() {
  final n = DateTime.now();
  final h = n.month <= 6 ? 'H1' : 'H2';
  return '${n.year}-$h';
}
String _kbkLabel(String kbk) => switch (kbk) {
      '101101' => 'ИПН по 910',
      '101110' => 'КПН (крупный)',
      '101111' => 'КПН (средний)',
      '105101' => 'НДС',
      '101201' => 'ИПН с з/п',
      '103101' => 'Соц. налог',
      '104301' => 'ОПВ',
      '104302' => 'ОПВР',
      '104101' => 'СО',
      '104406' => 'ВОСМС',
      '104407' => 'ООСМС',
      _        => kbk,
    };

// ── UI parts ─────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final _Alert alert;

  @override
  Widget build(BuildContext context) {
    final color = alert.level == 'red'
        ? EsepColors.expense
        : alert.level == 'yellow'
            ? EsepColors.warning
            : EsepColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            alert.level == 'red' ? Iconsax.warning_2 : Iconsax.info_circle,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alert.title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
              const SizedBox(height: 4),
              Text(alert.action,
                  style: const TextStyle(fontSize: 12, height: 1.5)),
            ],
          )),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: EsepColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Iconsax.wallet_check, size: 40, color: EsepColors.primary),
          ),
          const SizedBox(height: 18),
          const Text(
            'Контроль платежей в налоговую',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Добавляйте каждый платёж после оплаты в банке. Через 14 дней '
            'мы напомним проверить, разнеслось ли это в налоговой.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            icon: const Icon(Iconsax.add),
            label: const Text('Добавить первый платёж'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends ConsumerWidget {
  const _PaymentTile({required this.payment, required this.onChange});
  final _Payment payment;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visual = payment.statusVisual();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(
                payment.kbkLabel ?? payment.kbk,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              )),
              Text(
                '${payment.paidAmount.toStringAsFixed(0)} ₸',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Iconsax.calendar_1, size: 12, color: EsepColors.textSecondary),
              const SizedBox(width: 4),
              Text(payment.paidAt,
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(visual.text,
                    style: TextStyle(
                      color: visual.color, fontSize: 11, fontWeight: FontWeight.w600,
                    )),
              ),
            ]),
            if (payment.isPending) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Iconsax.tick_circle, size: 14),
                  label: const Text('Разнеслось', style: TextStyle(fontSize: 12)),
                  onPressed: () => _setStatus(ref, 'posted'),
                )),
                const SizedBox(width: 6),
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Iconsax.warning_2, size: 14),
                  label: const Text('Не туда', style: TextStyle(fontSize: 12)),
                  onPressed: () => _setStatus(ref, 'misposted'),
                )),
                const SizedBox(width: 6),
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Iconsax.close_circle, size: 14),
                  label: const Text('Не вижу', style: TextStyle(fontSize: 12)),
                  onPressed: () => _setStatus(ref, 'missing'),
                )),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setStatus(WidgetRef ref, String status) async {
    try {
      await ApiClient.patch(
        '/account/payments/${payment.id}',
        {'actual_status': status},
      );
      onChange();
    } catch (e) {
      // Покажем ошибку на верхнем уровне через snackBar
      // ignore: use_build_context_synchronously
    }
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: const [
            Text('Зачем нужен этот раздел',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            Text(
              'Бывает: вы перевели налог в банке, а на лицевом счёте налоговой '
              'эта сумма не появилась. Или ушла не на тот код (КБК), и формально '
              'у вас задолженность.\n\n'
              'Этот раздел напомнит вам через 14 дней проверить разноску — пока не поздно. '
              'Если что-то пошло не так, Консультант подскажет, какое заявление '
              'писать в КГД и куда обращаться.',
              style: TextStyle(fontSize: 13, height: 1.6, color: EsepColors.textPrimary),
            ),
            SizedBox(height: 16),
            Text('Как пользоваться',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text(
              '1. После каждой оплаты налога в банке нажмите "Добавить платёж"\n'
              '2. Через 14 дней зайдите в cabinet.salyk.kz → "Лицевой счёт"\n'
              '3. Найдите свой платёж и отметьте здесь:\n'
              '   • "Разнеслось" — всё ок\n'
              '   • "Не туда" — деньги ушли на другой КБК\n'
              '   • "Не вижу" — платежа вообще нет',
              style: TextStyle(fontSize: 13, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Iconsax.warning_2, size: 36, color: EsepColors.warning),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
        ]),
      ),
    );
  }
}
