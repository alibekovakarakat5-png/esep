import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/models/tax_profile.dart';
import '../../../core/providers/tax_profile_provider.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/kbk_service.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AddPaymentDialog(),
    );
    if (ok == true) {
      ref.invalidate(_paymentsProvider);
      ref.invalidate(_alertsProvider);
    }
  }
}

// ── Add Payment Dialog with KBK recommender ──────────────────────────────────

class _AddPaymentDialog extends ConsumerStatefulWidget {
  const _AddPaymentDialog();
  @override
  ConsumerState<_AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends ConsumerState<_AddPaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _docCtrl    = TextEditingController();
  final _periodCtrl = TextEditingController(text: _currentPeriod());

  PaymentTypeOption? _paymentType;
  String? _selectedKbk;
  KbkItem? _selectedKbkItem;
  KbkRecommendation? _recommendation;
  KbkValidation? _validation;
  DateTime _paidAt = DateTime.now();
  bool _saving = false;

  // Топ-9 типов платежей в порядке частоты
  static const _topTypes = [
    'income_tax',
    'social_tax',
    'social_self',
    'pension_self',
    'medical_self',
    'income_tax_employees',
    'pension_employees',
    'medical_employees',
    'vat',
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _docCtrl.dispose();
    _periodCtrl.dispose();
    super.dispose();
  }

  Future<void> _onPaymentTypeChanged(PaymentTypeOption? t, TaxProfile profile) async {
    setState(() {
      _paymentType = t;
      _recommendation = null;
      _validation = null;
    });
    if (t == null) return;
    try {
      final rec = await KbkService.recommend(profile: profile, paymentType: t.id);
      setState(() {
        _recommendation = rec;
        if (rec.recommended != null) {
          _selectedKbk = rec.recommended!.code;
          _selectedKbkItem = rec.recommended;
        }
      });
    } catch (_) {/* silent */}
  }

  Future<void> _validate(TaxProfile profile) async {
    if (_selectedKbk == null) return;
    try {
      final v = await KbkService.validate(
        profile: profile,
        code: _selectedKbk!,
        paymentType: _paymentType?.id,
      );
      setState(() => _validation = v);
    } catch (_) {/* silent */}
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(taxProfileProvider);

    return AlertDialog(
      title: const Text('Платёж в налоговую'),
      content: SizedBox(
        width: 420,
        child: asyncProfile.when(
          loading: () => const SizedBox(
            height: 100, child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _NoProfileBlock(message: e.toString()),
          data: (profile) => _form(profile),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Iconsax.tick_circle, size: 16),
          label: const Text('Сохранить'),
          onPressed: (_saving || _selectedKbk == null || _amountCtrl.text.trim().isEmpty)
              ? null
              : _save,
        ),
      ],
    );
  }

  Widget _form(TaxProfile profile) {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Тип платежа (вместо КБК-выпадайки)
        FutureBuilder<List<PaymentTypeOption>>(
          future: KbkService.listPaymentTypes(),
          builder: (_, snap) {
            if (!snap.hasData) return const LinearProgressIndicator();
            // Сортируем — топ платежей наверху
            final all = snap.data!;
            final top = _topTypes
                .map((id) => all.firstWhere((o) => o.id == id,
                    orElse: () => const PaymentTypeOption('', '')))
                .where((o) => o.id.isNotEmpty)
                .toList();
            final rest = all.where((o) => !_topTypes.contains(o.id)).toList();
            final ordered = [...top, ...rest];
            return DropdownButtonFormField<PaymentTypeOption>(
              value: _paymentType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Тип платежа',
                border: OutlineInputBorder(),
                hintText: 'Что вы оплачиваете?',
              ),
              items: ordered.map((o) => DropdownMenuItem(
                value: o,
                child: Text(o.label, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => _onPaymentTypeChanged(v, profile),
            );
          },
        ),
        const SizedBox(height: 10),

        // КБК с рекомендацией
        FutureBuilder<List<KbkItem>>(
          future: KbkService.listAll(),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final all = snap.data!;
            // Если есть рекомендация — поднимаем рекомендованный наверх,
            // потом alternatives, потом всё остальное.
            final ordered = <KbkItem>[];
            final added = <String>{};
            void add(KbkItem k) {
              if (added.add(k.code)) ordered.add(k);
            }
            if (_recommendation?.recommended != null) {
              add(_recommendation!.recommended!);
            }
            for (final k in _recommendation?.alternatives ?? <KbkItem>[]) { add(k); }
            for (final k in all) { add(k); }

            return DropdownButtonFormField<String>(
              value: _selectedKbk,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'КБК',
                border: const OutlineInputBorder(),
                helperText: _selectedKbkItem?.note,
                helperMaxLines: 2,
              ),
              items: ordered.map((k) {
                final isRec = _recommendation?.recommended?.code == k.code;
                return DropdownMenuItem(
                  value: k.code,
                  child: Row(children: [
                    if (isRec) ...[
                      const Icon(Iconsax.tick_circle, size: 14, color: EsepColors.primary),
                      const SizedBox(width: 4),
                    ],
                    Expanded(child: Text(
                      '${k.code} — ${k.label}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isRec ? FontWeight.w700 : FontWeight.normal,
                      ),
                    )),
                  ]),
                );
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedKbk = v;
                  _selectedKbkItem = all.firstWhere(
                    (k) => k.code == v,
                    orElse: () => all.first,
                  );
                });
                _validate(profile);
              },
            );
          },
        ),

        // Подсказка-плашка
        if (_recommendation?.recommended != null && _selectedKbk == _recommendation!.recommended!.code)
          _HintBanner(
            level: 'ok',
            text: _recommendation!.reason,
          )
        else if (_validation != null && !_validation!.ok)
          _HintBanner(
            level: _validation!.level,
            text: _validation!.message,
            actionLabel: _validation!.expected != null ? 'Использовать рекомендованный' : null,
            onAction: _validation!.expected != null ? () {
              setState(() {
                _selectedKbk = _validation!.expected!.code;
                _selectedKbkItem = _validation!.expected;
                _validation = null;
              });
            } : null,
          ),

        const SizedBox(height: 10),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(
            labelText: 'Сумма ₸', border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDate: _paidAt,
              );
              if (picked != null) setState(() => _paidAt = picked);
            },
            child: AbsorbPointer(
              child: TextField(
                controller: TextEditingController(text: _fmt(_paidAt)),
                decoration: const InputDecoration(
                  labelText: 'Дата оплаты', border: OutlineInputBorder(),
                  suffixIcon: Icon(Iconsax.calendar_1, size: 16),
                ),
              ),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _periodCtrl,
            decoration: const InputDecoration(
              labelText: 'Период (2026-H1)', border: OutlineInputBorder(),
            ),
          )),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _docCtrl,
          decoration: const InputDecoration(
            labelText: '№ платёжки (опционально)',
            border: OutlineInputBorder(),
          ),
        ),
      ]),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final amount = double.tryParse(
        _amountCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.'),
      ) ?? 0;
      if (amount <= 0) throw Exception('Сумма должна быть > 0');
      await ApiClient.post('/account/payments', {
        'kbk': _selectedKbk,
        'kbk_label': _selectedKbkItem?.label,
        'paid_amount': amount,
        'paid_at': _fmt(_paidAt),
        'tax_period': _periodCtrl.text.trim().isEmpty ? null : _periodCtrl.text.trim(),
        'payment_doc': _docCtrl.text.trim().isEmpty ? null : _docCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: EsepColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({
    required this.level, required this.text,
    this.actionLabel, this.onAction,
  });
  final String level;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = level == 'ok'
        ? const Color(0xFF1F7A3F)
        : level == 'red'
            ? EsepColors.expense
            : EsepColors.warning;
    final icon = level == 'ok' ? Iconsax.tick_circle : Iconsax.warning_2;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                text,
                style: TextStyle(fontSize: 12, color: color, height: 1.4),
              )),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoProfileBlock extends StatelessWidget {
  const _NoProfileBlock({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Не удалось загрузить ваш профиль: $message.\n'
          'Зайдите в Настройки → Налоговый профиль и заполните его.',
          style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
        ),
      );
}

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _currentPeriod() {
  final n = DateTime.now();
  final h = n.month <= 6 ? 'H1' : 'H2';
  return '${n.year}-$h';
}

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
