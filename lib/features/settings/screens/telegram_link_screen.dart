import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';

class _TgStatus {
  final bool linked;
  final String? username;
  final String? linkedAt;
  const _TgStatus({required this.linked, this.username, this.linkedAt});
  factory _TgStatus.fromJson(Map<String, dynamic> j) => _TgStatus(
        linked: (j['linked'] as bool?) ?? false,
        username: j['username'] as String?,
        linkedAt: j['linked_at']?.toString(),
      );
}

final _tgStatusProvider = FutureProvider.autoDispose<_TgStatus>((ref) async {
  final j = await ApiClient.get('/auth/telegram/status') as Map<String, dynamic>;
  return _TgStatus.fromJson(j);
});

class TelegramLinkScreen extends ConsumerWidget {
  const TelegramLinkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_tgStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Привязка Telegram')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (s) => s.linked
            ? _LinkedView(status: s, onChange: () => ref.invalidate(_tgStatusProvider))
            : _NotLinkedView(onChange: () => ref.invalidate(_tgStatusProvider)),
      ),
    );
  }
}

// ── Not linked: запросить ссылку ───────────────────────────────────────────────

class _NotLinkedView extends StatefulWidget {
  const _NotLinkedView({required this.onChange});
  final VoidCallback onChange;
  @override
  State<_NotLinkedView> createState() => _NotLinkedViewState();
}

class _NotLinkedViewState extends State<_NotLinkedView> {
  String? _deeplink;
  String? _botUsername;
  int? _expiresInSec;
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final j = await ApiClient.post('/auth/telegram/bind-link', {})
          as Map<String, dynamic>;
      setState(() {
        _deeplink = j['deeplink'] as String?;
        _botUsername = j['bot_username'] as String?;
        _expiresInSec = j['expires_in_seconds'] as int?;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF229ED9).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF229ED9).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF229ED9), shape: BoxShape.circle,
              ),
              child: const Icon(Iconsax.send_2, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text(
              'Привязка Telegram нужна, чтобы\nвосстановить пароль если забудете',
              style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600),
            )),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('Как работает',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        const _Step(num: 1, text: 'Нажмите «Получить ссылку»'),
        const _Step(num: 2, text: 'Откроется бот @esep_bot в Telegram'),
        const _Step(
          num: 3,
          text: 'Бот покажет ваш email и спросит «Это вы?». '
                'Подтвердите — и привязка готова.',
        ),
        const SizedBox(height: 20),
        if (_deeplink == null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Iconsax.link_2, size: 18),
              label: const Text('Получить ссылку'),
              onPressed: _busy ? null : _request,
            ),
          )
        else _LinkBlock(
          deeplink: _deeplink!,
          botUsername: _botUsername ?? 'esep_bot',
          expiresIn: _expiresInSec ?? 600,
          onRefreshStatus: widget.onChange,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EsepColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Iconsax.shield_tick, size: 18, color: EsepColors.primary),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Безопасно: ссылка одноразовая, действует 10 минут. Бот покажет '
              'ваш email и потребует подтверждение в Telegram. Никто не сможет '
              'привязать ваш аккаунт к чужому Telegram без вашего ручного '
              'подтверждения в самом мессенджере.',
              style: TextStyle(fontSize: 12, height: 1.5),
            )),
          ]),
        ),
      ],
    );
  }
}

class _LinkBlock extends StatelessWidget {
  const _LinkBlock({
    required this.deeplink,
    required this.botUsername,
    required this.expiresIn,
    required this.onRefreshStatus,
  });
  final String deeplink;
  final String botUsername;
  final int expiresIn;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Iconsax.send_2, size: 18),
          label: Text('Открыть @$botUsername'),
          onPressed: () async {
            final uri = Uri.parse(deeplink);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Iconsax.copy, size: 14),
        label: const Text('Скопировать ссылку'),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: deeplink));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ссылка скопирована')),
          );
        },
      ),
      const SizedBox(height: 12),
      Text(
        'Ссылка действует ${(expiresIn / 60).round()} минут.\n'
        'После подтверждения в боте — нажмите ниже, чтобы обновить статус.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        icon: const Icon(Iconsax.refresh, size: 14),
        label: const Text('Я подтвердил, проверить'),
        onPressed: onRefreshStatus,
      ),
    ]);
  }
}

// ── Linked: показать статус и кнопку отвязать ──────────────────────────────────

class _LinkedView extends StatefulWidget {
  const _LinkedView({required this.status, required this.onChange});
  final _TgStatus status;
  final VoidCallback onChange;
  @override
  State<_LinkedView> createState() => _LinkedViewState();
}

class _LinkedViewState extends State<_LinkedView> {
  bool _busy = false;

  Future<void> _unbind() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отвязать Telegram?'),
        content: const Text(
          'Вы больше не сможете восстановить пароль через Telegram. '
          'Это можно будет сделать только обратившись в поддержку.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: EsepColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отвязать'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ApiClient.delete('/auth/telegram/unbind');
      widget.onChange();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final username = s.username != null ? '@${s.username}' : 'Telegram';
    final linkedAt = (s.linkedAt ?? '').split('T').first;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F7A3F).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F7A3F).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF1F7A3F), shape: BoxShape.circle,
              ),
              child: const Icon(Iconsax.tick_circle, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (linkedAt.isNotEmpty)
                  Text('Привязан $linkedAt',
                      style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              ],
            )),
          ]),
        ),
        const SizedBox(height: 20),
        const Text(
          'Что это даёт',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        const _Bullet(text: 'Сброс пароля — код приходит вам в Telegram за секунду'),
        const _Bullet(text: 'Безопасные уведомления о смене пароля и подозрительных входах'),
        const _Bullet(text: 'Тариф бота без лимитов'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Iconsax.unlock, size: 18, color: EsepColors.expense),
            label: const Text('Отвязать Telegram',
                style: TextStyle(color: EsepColors.expense)),
            onPressed: _busy ? null : _unbind,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: EsepColors.expense),
            ),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.num, required this.text});
  final int num;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: EsepColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(num.toString(),
              style: const TextStyle(
                color: EsepColors.primary,
                fontWeight: FontWeight.w800, fontSize: 12,
              )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
        )),
      ]),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 5, right: 8),
            child: Icon(Icons.check_circle, size: 14, color: EsepColors.primary),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5))),
        ]),
      );
}
