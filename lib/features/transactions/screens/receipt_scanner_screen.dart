import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/receipt_scanner_service.dart';
import '../../../core/providers/transaction_provider.dart';

class ReceiptScannerScreen extends ConsumerStatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  ConsumerState<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends ConsumerState<ReceiptScannerScreen> {
  final _picker = ImagePicker();
  File? _image;
  ReceiptData? _result;
  bool _scanning = false;
  String? _error;

  // Editable fields
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() {
        _image = File(picked.path);
        _result = null;
        _error = null;
        _scanning = true;
      });

      final data = await ReceiptScannerService.scanReceipt(_image!);

      setState(() {
        _result = data;
        _scanning = false;
        if (data.storeName != null) _titleCtrl.text = data.storeName!;
        if (data.totalAmount != null) _amountCtrl.text = data.totalAmount!.toStringAsFixed(0);
        if (data.date != null) _date = data.date!;
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _error = 'Ошибка сканирования: $e';
      });
    }
  }

  void _saveTransaction() {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(' ', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректную сумму')),
      );
      return;
    }

    final title = _titleCtrl.text.trim().isEmpty ? 'Чек' : _titleCtrl.text.trim();

    ref.read(transactionProvider.notifier).add(
          title: title,
          amount: amount,
          isIncome: false,
          date: _date,
          source: 'чек',
          category: 'Покупки',
        );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Расход "$title" на ${NumberFormat('#,##0', 'ru_RU').format(amount)} ₸ добавлен')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Сканер чеков')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Pick image buttons
          if (_image == null) ...[
            const SizedBox(height: 40),
            const Icon(Iconsax.scan, size: 64, color: EsepColors.textDisabled),
            const SizedBox(height: 16),
            const Text(
              'Сфотографируйте чек или выберите\nиз галереи для автоматического\nдобавления расхода',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: EsepColors.textSecondary),
            ),
            const SizedBox(height: 32),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Iconsax.camera),
                  label: const Text('Камера'),
                  style: FilledButton.styleFrom(
                    backgroundColor: EsepColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Iconsax.gallery),
                  label: const Text('Галерея'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ]),
          ],

          // Scanning indicator
          if (_scanning) ...[
            const SizedBox(height: 40),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            const Center(child: Text('Распознаём текст...', style: TextStyle(color: EsepColors.textSecondary))),
          ],

          // Error
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: EsepColors.expense.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Iconsax.warning_2, color: EsepColors.expense, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: EsepColors.expense))),
                ]),
              ),
            ),
          ],

          // Results
          if (_result != null && !_scanning) ...[
            // Image preview
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!, height: 200, fit: BoxFit.cover, width: double.infinity),
              ),
            const SizedBox(height: 16),

            // Recognition status
            Card(
              color: EsepColors.income.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Iconsax.tick_circle, color: EsepColors.income, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'Распознано ${_result!.rawLines.length} строк. Проверьте данные.',
                    style: const TextStyle(fontSize: 12, color: EsepColors.income),
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Editable fields
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Название (магазин)',
                prefixIcon: Icon(Iconsax.shop, color: EsepColors.primary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Сумма, ₸',
                prefixIcon: Icon(Iconsax.money_3, color: EsepColors.expense),
              ),
            ),
            const SizedBox(height: 12),

            // Date picker
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Iconsax.calendar_1, color: EsepColors.primary),
              title: Text(dateFmt.format(_date)),
              subtitle: const Text('Дата чека'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 16),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _saveTransaction,
                icon: const Icon(Iconsax.add_circle),
                label: const Text('Добавить расход'),
                style: FilledButton.styleFrom(
                  backgroundColor: EsepColors.expense,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Re-scan button
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _image = null;
                  _result = null;
                  _error = null;
                  _titleCtrl.clear();
                  _amountCtrl.clear();
                  _date = DateTime.now();
                }),
                icon: const Icon(Iconsax.refresh, size: 18),
                label: const Text('Сканировать другой чек'),
              ),
            ),
            const SizedBox(height: 16),

            // Raw text (collapsible)
            ExpansionTile(
              title: const Text('Распознанный текст', style: TextStyle(fontSize: 13)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EsepColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _result!.rawLines.join('\n'),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: EsepColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
