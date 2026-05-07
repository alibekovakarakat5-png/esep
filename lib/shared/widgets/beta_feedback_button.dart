// BetaFeedbackButton — плавающая кнопка "🧪 Сообщить о баге".
//
// Виден ТОЛЬКО пользователям с ролью is_beta_tester (бухгалтер-консультант,
// фокус-группа). Обычные клиенты не видят и даже не знают что эта кнопка есть.
//
// Использование (вкладывать в любой Scaffold):
//   floatingActionButton: const BetaFeedbackButton(screen: 'taxes'),
//
// Передавай screen='form910' / 'invoices' / 'dashboard' и т.д. — это поможет
// Каракат разобрать отчёты по экранам.

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/feedback_service.dart';

class BetaFeedbackButton extends StatefulWidget {
  /// Идентификатор экрана — попадёт в Telegram-уведомление.
  final String screen;

  /// Если true — рендерится не как FAB, а как маленький IconButton (для AppBar).
  final bool compact;

  const BetaFeedbackButton({
    super.key,
    required this.screen,
    this.compact = false,
  });

  @override
  State<BetaFeedbackButton> createState() => _BetaFeedbackButtonState();
}

class _BetaFeedbackButtonState extends State<BetaFeedbackButton> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    AuthService.isBetaTester().then((v) {
      if (!mounted) return;
      setState(() => _allowed = v);
    });
  }

  Future<void> _open() async {
    final result = await showDialog<_FeedbackPayload>(
      context: context,
      builder: (_) => _FeedbackDialog(screen: widget.screen),
    );
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await FeedbackService.send(
        screen: widget.screen,
        message: result.message,
        severity: result.severity,
      );
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade600,
          content: const Row(
            children: [
              Icon(Iconsax.tick_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Отчёт отправлен. Спасибо!')),
            ],
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Не удалось отправить: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed != true) return const SizedBox.shrink();

    if (widget.compact) {
      return IconButton(
        tooltip: 'Сообщить о баге (бета-тест)',
        icon: const Icon(Icons.bug_report_outlined),
        onPressed: _open,
      );
    }

    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      onPressed: _open,
      backgroundColor: cs.error.withValues(alpha: 0.9),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.bug_report_outlined, size: 18),
      label: const Text(
        'Сообщить о баге',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      tooltip: 'Виден только бета-тестировщикам',
    );
  }
}

class _FeedbackPayload {
  final String message;
  final String severity;
  const _FeedbackPayload(this.message, this.severity);
}

class _FeedbackDialog extends StatefulWidget {
  final String screen;
  const _FeedbackDialog({required this.screen});

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _ctrl = TextEditingController();
  String _severity = 'normal';
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    Navigator.of(context).pop(_FeedbackPayload(text, _severity));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bug_report_outlined, color: cs.error, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Сообщить о баге',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Экран: ${widget.screen}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 6,
              maxLength: 4000,
              decoration: InputDecoration(
                hintText:
                    'Что не так? Что бы вы изменили? Опишите как можно конкретнее: что нажали, что ожидали увидеть, что увидели.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Серьёзность',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                _sevChip('low', '🔵 Идея'),
                _sevChip('normal', '🟢 Обычная'),
                _sevChip('high', '🟠 Важная'),
                _sevChip('critical', '🔴 Критичная'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Iconsax.send_2, size: 16),
          label: const Text('Отправить'),
        ),
      ],
    );
  }

  Widget _sevChip(String key, String label) {
    final selected = _severity == key;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _severity = key),
    );
  }
}
