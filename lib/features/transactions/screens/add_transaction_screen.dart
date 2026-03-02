import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/transaction_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, required this.isIncome});
  final bool isIncome;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _clientCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _source = 'kaspi';
  DateTime _date = DateTime.now();

  static const _sources = ['kaspi', 'halyk', 'forte', 'наличные', 'перевод', 'карта', 'другое'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _clientCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isIncome ? EsepColors.income : EsepColors.expense;
    final label = widget.isIncome ? 'Доход' : 'Расход';

    return Scaffold(
      appBar: AppBar(
        title: Text('Новый $label'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Amount
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                Icon(
                  widget.isIncome ? Iconsax.arrow_circle_up : Iconsax.arrow_circle_down,
                  color: color, size: 32,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: color),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(fontSize: 32, color: color.withValues(alpha: 0.3)),
                    suffixText: '₸',
                    suffixStyle: TextStyle(fontSize: 24, color: color),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Введите сумму';
                    if (double.tryParse(v.replaceAll(' ', '')) == null) return 'Некорректная сумма';
                    return null;
                  },
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // Title
            TextFormField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Описание',
                prefixIcon: Icon(Iconsax.document_text, color: color),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Введите описание' : null,
            ),
            const SizedBox(height: 16),

            // Client
            TextFormField(
              controller: _clientCtrl,
              decoration: InputDecoration(
                labelText: 'Контрагент',
                prefixIcon: Icon(Iconsax.user, color: color),
              ),
            ),
            const SizedBox(height: 16),

            // Source
            DropdownButtonFormField<String>(
              initialValue: _source,
              decoration: InputDecoration(
                labelText: 'Источник',
                prefixIcon: Icon(Iconsax.wallet_2, color: color),
              ),
              items: _sources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _source = v ?? 'kaspi'),
            ),
            const SizedBox(height: 16),

            // Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Iconsax.calendar_1, color: color),
              title: Text(DateFormat('dd MMMM yyyy', 'ru_RU').format(_date)),
              subtitle: const Text('Дата операции'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Note
            TextFormField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Заметка (необязательно)',
                prefixIcon: Icon(Iconsax.note_1, color: color),
              ),
            ),
            const SizedBox(height: 32),

            // Save
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: _save,
              child: Text('Сохранить $label'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.replaceAll(' ', ''));
    ref.read(transactionProvider.notifier).add(
          title: _titleCtrl.text.trim(),
          amount: amount,
          isIncome: widget.isIncome,
          date: _date,
          clientName: _clientCtrl.text.trim().isEmpty ? null : _clientCtrl.text.trim(),
          source: _source,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
    Navigator.of(context).pop();
  }
}
