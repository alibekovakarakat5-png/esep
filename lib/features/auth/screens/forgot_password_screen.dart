import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/responsive_form_shell.dart';

/// Экран сброса пароля — 3 шага:
/// 1. Email → отправляем 6-значный код в Telegram
/// 2. Ввод кода → получаем reset_token
/// 3. Новый пароль → меняем

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { email, code, newPassword, done }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  _Step _step = _Step.email;
  final _emailCtrl = TextEditingController();
  final _codeCtrl  = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _newPass2Ctrl = TextEditingController();
  String? _resetToken;
  String? _error;
  String? _info;
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    _newPass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!email.contains('@')) {
      setState(() => _error = 'Введите корректный email');
      return;
    }
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      final r = await ApiClient.post('/auth/forgot-password', {'email': email})
          as Map<String, dynamic>;
      setState(() {
        _info = (r['message'] ?? '') as String;
        _step = _Step.code;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Не удалось связаться с сервером');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Код должен быть 6-значным');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await ApiClient.post('/auth/verify-reset-code', {
        'email': _emailCtrl.text.trim().toLowerCase(),
        'code':  code,
      }) as Map<String, dynamic>;
      setState(() {
        _resetToken = (r['reset_token'] ?? '') as String;
        _step = _Step.newPassword;
        _info = null;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Не удалось связаться с сервером');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final p1 = _newPassCtrl.text;
    final p2 = _newPass2Ctrl.text;
    if (p1.length < 8) {
      setState(() => _error = 'Пароль должен быть не короче 8 символов');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ApiClient.post('/auth/reset-password', {
        'reset_token':  _resetToken,
        'new_password': p1,
      });
      setState(() => _step = _Step.done);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Не удалось связаться с сервером');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: responsivePageBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Восстановление пароля'),
      ),
      body: ResponsiveFormShell(
        padding: const EdgeInsets.all(24),
        child: switch (_step) {
          _Step.email       => _emailStep(),
          _Step.code        => _codeStep(),
          _Step.newPassword => _newPasswordStep(),
          _Step.done        => _doneStep(),
        },
      ),
    );
  }

  // ── Steps ──────────────────────────────────────────────────────────────────

  Widget _emailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          icon: Iconsax.sms,
          title: 'Шаг 1 из 3 — ваш email',
          subtitle:
              'Мы отправим 6-значный код в ваш Telegram, привязанный к этому аккаунту.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email', border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _requestCode(),
        ),
        if (_error != null) _ErrorBanner(text: _error!),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _requestCode,
            child: _busy ? _spinner() : const Text('Отправить код'),
          ),
        ),
        const SizedBox(height: 8),
        const _HelpText(
          text: 'Если у вас не привязан Telegram — обратитесь в поддержку '
                'через Telegram @alibekovakarakat или напишите на hello@esep.kz',
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          icon: Iconsax.message_question,
          title: 'Шаг 2 из 3 — код из Telegram',
          subtitle:
              'Откройте Telegram. Бот @esep_bot прислал вам 6-значный код. '
              'Введите его сюда.',
        ),
        if (_info != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: EsepColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_info!,
                style: const TextStyle(fontSize: 12, height: 1.5)),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            counterText: '',
            border: OutlineInputBorder(),
            hintText: '000000',
          ),
          onSubmitted: (_) => _verifyCode(),
        ),
        if (_error != null) _ErrorBanner(text: _error!),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _verifyCode,
            child: _busy ? _spinner() : const Text('Проверить код'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _requestCode,
          child: const Text('Отправить код заново'),
        ),
      ],
    );
  }

  Widget _newPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          icon: Iconsax.lock,
          title: 'Шаг 3 из 3 — новый пароль',
          subtitle: 'Минимум 8 символов. Используйте сложный пароль.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _newPassCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Новый пароль', border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPass2Ctrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Повторите пароль', border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _resetPassword(),
        ),
        if (_error != null) _ErrorBanner(text: _error!),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _resetPassword,
            child: _busy ? _spinner() : const Text('Установить новый пароль'),
          ),
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF1F7A3F).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Iconsax.tick_circle, size: 40, color: Color(0xFF1F7A3F)),
        ),
        const SizedBox(height: 18),
        const Text('Пароль обновлён',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Мы отправили подтверждение в ваш Telegram. Если это были не вы — '
            'смените пароль ещё раз и временно отвяжите Telegram через настройки.',
            textAlign: TextAlign.center,
            style: TextStyle(color: EsepColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Iconsax.login_1, size: 18),
            label: const Text('Войти с новым паролем'),
            onPressed: () => context.go('/auth'),
          ),
        ),
      ],
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static Widget _spinner() => const SizedBox(
        height: 20, width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: EsepColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 28, color: EsepColors.primary),
        ),
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(
              fontSize: 13, color: EsepColors.textSecondary, height: 1.5,
            )),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: EsepColors.expense.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: EsepColors.expense, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
              style: const TextStyle(color: EsepColors.expense, fontSize: 13))),
        ]),
      ),
    );
  }
}

class _HelpText extends StatelessWidget {
  const _HelpText({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text,
          style: const TextStyle(
            fontSize: 12, color: EsepColors.textSecondary, height: 1.5,
          )),
    );
  }
}
