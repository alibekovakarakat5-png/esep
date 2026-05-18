/// Экран для теста конкретного сервиса Platform API.
///
/// Открывается из ServiceCard. Содержит:
///   - Форму ввода параметров (зависит от serviceCode)
///   - Кнопку "Выполнить"
///   - Блок с JSON-результатом
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/platform_api_service.dart';

class ServiceTestScreen extends StatefulWidget {
  final String serviceCode;
  final String title;
  final String apiKey;

  const ServiceTestScreen({
    super.key,
    required this.serviceCode,
    required this.title,
    required this.apiKey,
  });

  @override
  State<ServiceTestScreen> createState() => _ServiceTestScreenState();
}

class _ServiceTestScreenState extends State<ServiceTestScreen> {
  final _iinCtrl = TextEditingController(text: '850101100012');
  final _binCtrl = TextEditingController(text: '850101100012');
  final _amountCtrl = TextEditingController(text: '50000');
  final _orderCtrl = TextEditingController();
  final _cancelReasonCtrl = TextEditingController(text: 'Курьер отказался от доставки');

  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _orderCtrl.text = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _iinCtrl.dispose();
    _binCtrl.dispose();
    _amountCtrl.dispose();
    _orderCtrl.dispose();
    _cancelReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      late Map<String, dynamic> res;
      switch (widget.serviceCode) {
        case 'iin_validate':
          res = await PlatformApiService.validateIin(
              _iinCtrl.text.trim(), widget.apiKey);
          break;
        case 'taxpayer_info':
          res = await PlatformApiService.taxpayerInfo(
              _binCtrl.text.trim(), widget.apiKey);
          break;
        case 'income_limit':
          res = await PlatformApiService.incomeLimitStatus(
              _iinCtrl.text.trim(), widget.apiKey);
          break;
        case 'process_payment':
          res = await PlatformApiService.processPayment(
            courierIin: _iinCtrl.text.trim(),
            amount: double.tryParse(_amountCtrl.text) ?? 0,
            orderId: _orderCtrl.text.trim(),
            apiKey: widget.apiKey,
          );
          break;
        case 'cancel_order':
          res = await PlatformApiService.cancelOrder(
            orderId: _orderCtrl.text.trim(),
            reason: _cancelReasonCtrl.text.trim(),
            apiKey: widget.apiKey,
          );
          break;
        default:
          res = {
            'mode': 'demo',
            'message': 'Этот сервис в demo-режиме. '
                'Реальная интеграция возможна после получения договора с КГД ИСНА.',
            'service_code': widget.serviceCode,
          };
      }
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF0F2B46),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFormCard(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loading ? null : _execute,
            icon: _loading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Iconsax.play_circle),
            label: Text(_loading ? 'Выполняем...' : 'Выполнить запрос'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFF0EA5E9),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null) _buildErrorCard(),
          if (_result != null) _buildResultCard(),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Параметры запроса',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          ..._buildFieldsForService(),
        ],
      ),
    );
  }

  List<Widget> _buildFieldsForService() {
    switch (widget.serviceCode) {
      case 'iin_validate':
      case 'income_limit':
        return [
          _field(_iinCtrl, 'ИИН (12 цифр)',
              hint: 'Например: 850101100012'),
        ];
      case 'taxpayer_info':
        return [
          _field(_binCtrl, 'БИН / ИИН (12 цифр)',
              hint: 'Введите БИН компании или ИИН ФЛ'),
        ];
      case 'process_payment':
        return [
          _field(_iinCtrl, 'ИИН курьера', hint: '12 цифр'),
          const SizedBox(height: 10),
          _field(_amountCtrl, 'Сумма выплаты (₸)',
              hint: 'Например: 50000', keyboard: TextInputType.number),
          const SizedBox(height: 10),
          _field(_orderCtrl, 'ID заказа',
              hint: 'Уникальный идентификатор'),
        ];
      case 'cancel_order':
        return [
          _field(_orderCtrl, 'ID заказа для отмены',
              hint: 'Уникальный идентификатор'),
          const SizedBox(height: 10),
          _field(_cancelReasonCtrl, 'Причина отмены'),
        ];
      default:
        return [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '⚠ Этот сервис в demo-режиме. Реальная интеграция с КГД '
              'ИСНА — после оформления договора. Параметры не нужны.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ];
    }
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Iconsax.warning_2, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              _error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final pretty = const JsonEncoder.withIndent('  ').convert(_result);
    final decision = _result?['decision'] as String?;
    final ok = _result?['ok'] == true ||
        _result?['valid'] == true ||
        _result?['can_pay'] == true ||
        _result?['recorded'] == true ||
        _result?['found_in_registry'] == true ||
        decision == 'PROCEED';

    final isWarning = decision == 'WARNING';
    final color = isWarning
        ? const Color(0xFFF59E0B)
        : ok
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  ok ? Iconsax.tick_circle : (isWarning ? Iconsax.warning_2 : Iconsax.close_circle),
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  ok ? 'Запрос выполнен успешно' :
                       isWarning ? 'Выполнено с предупреждением' :
                       'Ошибка / отказ',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Iconsax.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pretty));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано в буфер')),
                    );
                  },
                  tooltip: 'Скопировать JSON',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              pretty,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF334155),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
