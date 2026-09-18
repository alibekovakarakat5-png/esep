import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/accounting_client.dart';
import '../../../core/providers/accounting_provider.dart';

const _uuid = Uuid();

class AddAccountingClientScreen extends ConsumerStatefulWidget {
  const AddAccountingClientScreen({super.key, this.existing});
  final AccountingClient? existing;

  @override
  ConsumerState<AddAccountingClientScreen> createState() =>
      _AddAccountingClientScreenState();
}

class _AddAccountingClientScreenState
    extends ConsumerState<AddAccountingClientScreen> {
  final _nameCtrl = TextEditingController();
  final _binCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late final String _clientId;
  bool _saving = false;

  ClientEntityType _entityType = ClientEntityType.ip;
  ClientTaxRegime _regime = ClientTaxRegime.simplified910;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _clientId = c?.id ?? _uuid.v4();
    if (c != null) {
      _nameCtrl.text = c.name;
      _binCtrl.text = c.binOrIin;
      _feeCtrl.text = c.monthlyFee > 0 ? c.monthlyFee.toStringAsFixed(0) : '';
      _notesCtrl.text = c.notes ?? '';
      _entityType = c.entityType;
      _regime = c.regime;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _binCtrl.dispose();
    _feeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название/ФИО')),
      );
      return;
    }

    final fee = double.tryParse(_feeCtrl.text.replaceAll(' ', '')) ?? 0;

    // Take the latest loaded record, preserving fields this form does not edit.
    final current = ref
            .read(accountingProvider)
            .where((c) => c.id == _clientId)
            .firstOrNull ??
        widget.existing;
    final base = current ??
        AccountingClient(
          id: _clientId,
          name: '',
          binOrIin: '',
          entityType: _entityType,
          regime: _regime,
          checklist: _defaultChecklist(_regime),
        );
    final client = base.copyWith(
      name: name,
      binOrIin: _binCtrl.text.trim(),
      entityType: _entityType,
      regime: _regime,
      monthlyFee: fee,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      clearNotes: _notesCtrl.text.trim().isEmpty,
    );

    final notifier = ref.read(accountingProvider.notifier);
    setState(() => _saving = true);
    try {
      if (widget.existing != null) {
        await notifier.updateClient(client);
      } else {
        await notifier.addClient(client);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Сохранение не подтверждено. Данные остались в форме. Повторите попытку: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Редактировать клиента' : 'Новый клиент'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Сохранить',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Entity type toggle ─────────────────────────────────────────
            const Text('Тип',
                style: TextStyle(
                    fontSize: 13,
                    color: EsepColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
                children: ClientEntityType.values
                    .map((t) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: t == ClientEntityType.ip ? 8 : 0),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _entityType == t
                                    ? EsepColors.primary.withValues(alpha: 0.1)
                                    : null,
                                side: BorderSide(
                                  color: _entityType == t
                                      ? EsepColors.primary
                                      : EsepColors.divider,
                                ),
                              ),
                              onPressed: () => setState(() => _entityType = t),
                              child: Text(t.label,
                                  style: TextStyle(
                                    color: _entityType == t
                                        ? EsepColors.primary
                                        : EsepColors.textSecondary,
                                    fontWeight: _entityType == t
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  )),
                            ),
                          ),
                        ))
                    .toList()),

            const SizedBox(height: 20),

            // ── Name ───────────────────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _entityType == ClientEntityType.ip
                    ? 'ФИО предпринимателя'
                    : 'Название организации',
                prefixIcon: const Icon(Iconsax.user, size: 18),
              ),
            ),
            const SizedBox(height: 12),

            // ── BIN / IIN ──────────────────────────────────────────────────
            TextField(
              controller: _binCtrl,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: InputDecoration(
                labelText: _entityType == ClientEntityType.ip
                    ? 'ИИН (12 цифр)'
                    : 'БИН (12 цифр)',
                prefixIcon: const Icon(Iconsax.card, size: 18),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),

            // ── Tax regime ─────────────────────────────────────────────────
            const Text('Налоговый режим',
                style: TextStyle(
                    fontSize: 13,
                    color: EsepColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ClientTaxRegime.values
                  .map((r) => ChoiceChip(
                        label: Text(r.label),
                        selected: _regime == r,
                        onSelected: (_) => setState(() => _regime = r),
                        selectedColor:
                            EsepColors.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: _regime == r
                              ? EsepColors.primary
                              : EsepColors.textSecondary,
                          fontWeight: _regime == r
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),

            // ── Monthly fee ────────────────────────────────────────────────
            TextField(
              controller: _feeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Мой гонорар (₸/мес)',
                prefixIcon: Icon(Iconsax.wallet_money, size: 18),
                hintText: '0',
              ),
            ),
            const SizedBox(height: 12),

            // ── Notes ──────────────────────────────────────────────────────
            TextField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Заметки (необязательно)',
                prefixIcon: Icon(Icons.notes_outlined, size: 18),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(
                    _saving
                        ? 'Сохранение…'
                        : (isEdit ? 'Сохранить изменения' : 'Добавить клиента'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

List<DocChecklistItem> _defaultChecklist(ClientTaxRegime regime) {
  final now = DateTime.now();
  final label = '${_monthName(now.month)} ${now.year}';
  return switch (regime) {
    ClientTaxRegime.simplified910 || ClientTaxRegime.patent => [
        DocChecklistItem(id: _uuid.v4(), label: 'Банковская выписка за $label'),
        DocChecklistItem(id: _uuid.v4(), label: 'Реестр доходов за $label'),
      ],
    ClientTaxRegime.esp => [
        DocChecklistItem(id: _uuid.v4(), label: 'Выписка по счёту за $label'),
      ],
    ClientTaxRegime.our => [
        DocChecklistItem(id: _uuid.v4(), label: 'Банковская выписка за $label'),
        DocChecklistItem(id: _uuid.v4(), label: 'Авансовые отчёты за $label'),
        DocChecklistItem(id: _uuid.v4(), label: 'Акты выполненных работ'),
        DocChecklistItem(id: _uuid.v4(), label: 'Счёт-фактуры за $label'),
      ],
  };
}

String _monthName(int month) => const [
      '',
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек'
    ][month];
