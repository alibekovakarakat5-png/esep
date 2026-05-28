import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants/legal_docs.dart';
import '../../../core/providers/legal_consent_provider.dart';
import '../../../core/services/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _consentAccepted = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(email, pass);
      if (mounted) context.go('/dashboard');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Нет соединения с сервером');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || email.isEmpty || pass.isEmpty) return;
    if (!_consentAccepted) {
      setState(() => _error =
          'Подтвердите согласие с условиями использования');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).register(
        email, pass, name,
        phone: phone.isEmpty ? null : phone,
      );
      await ref.read(legalConsentProvider.notifier).accept();
      if (mounted) context.go('/dashboard');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Нет соединения с сервером');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 600;

    return Scaffold(
      backgroundColor: isWide ? const Color(0xFFF5F6FA) : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 24 : 0,
              vertical: isWide ? 32 : 0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                decoration: isWide
                    ? BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Center(
                      child: Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: EsepColors.primary,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: EsepColors.primary.withValues(alpha: 0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('E',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                              )),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: Text('Esep',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          )),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Учёт для вашего бизнеса',
                        style: TextStyle(
                          color: EsepColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Tabs
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: TabBar(
                        controller: _tabs,
                        labelColor: Colors.white,
                        unselectedLabelColor: EsepColors.textSecondary,
                        indicator: BoxDecoration(
                          color: EsepColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                        ),
                        tabs: const [
                          Tab(text: 'Войти'),
                          Tab(text: 'Регистрация'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: EsepColors.expense.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              color: EsepColors.expense, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: EsepColors.expense,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Tab views — без Expanded чтобы высота определялась контентом
                    SizedBox(
                      height: _tabs.index == 0 ? 230 : 460,
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _LoginTab(
                            emailCtrl: _emailCtrl,
                            passCtrl: _passCtrl,
                            loading: _loading,
                            onLogin: _login,
                          ),
                          _RegisterTab(
                            nameCtrl: _nameCtrl,
                            emailCtrl: _emailCtrl,
                            passCtrl: _passCtrl,
                            phoneCtrl: _phoneCtrl,
                            loading: _loading,
                            consentAccepted: _consentAccepted,
                            onConsentChanged: (v) =>
                                setState(() => _consentAccepted = v),
                            onRegister: _register,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Demo button
                    OutlinedButton.icon(
                      icon: const Icon(Iconsax.eye, size: 18),
                      label: const Text('Посмотреть без входа'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                            color: EsepColors.primary.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        ref.read(authProvider.notifier).enterDemo();
                      },
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Демо-данные — без регистрации',
                        style: TextStyle(
                          fontSize: 12,
                          color: EsepColors.textDisabled,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginTab extends StatelessWidget {
  const _LoginTab({
    required this.emailCtrl,
    required this.passCtrl,
    required this.loading,
    required this.onLogin,
  });
  final TextEditingController emailCtrl, passCtrl;
  final bool loading;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Пароль'),
          onSubmitted: (_) => onLogin(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => _HelpRequestDialog(initialEmail: emailCtrl.text.trim()),
              );
            },
            icon: const Icon(Iconsax.key, size: 16),
            label: const Text('Забыл пароль?'),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: loading ? null : onLogin,
            child: loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Войти'),
          ),
        ),
      ],
    );
  }
}

class _RegisterTab extends StatelessWidget {
  const _RegisterTab({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.passCtrl,
    required this.phoneCtrl,
    required this.loading,
    required this.consentAccepted,
    required this.onConsentChanged,
    required this.onRegister,
  });
  final TextEditingController nameCtrl, emailCtrl, passCtrl, phoneCtrl;
  final bool loading;
  final bool consentAccepted;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final canSubmit = consentAccepted && !loading;
    return SingleChildScrollView(
      child: Column(
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Имя или название ИП',
              hintText: 'Например: Айгуль или ИП Сулейменова',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Телефон (необязательно)',
              hintText: '+7 777 123 45 67',
              helperText: 'Для связи с поддержкой',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль'),
            onSubmitted: (_) {
              if (canSubmit) onRegister();
            },
          ),
          const SizedBox(height: 14),
          _ConsentCheckbox(
            accepted: consentAccepted,
            onChanged: onConsentChanged,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: canSubmit ? onRegister : null,
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Создать аккаунт'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentCheckbox extends StatefulWidget {
  const _ConsentCheckbox({required this.accepted, required this.onChanged});
  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  State<_ConsentCheckbox> createState() => _ConsentCheckboxState();
}

class _ConsentCheckboxState extends State<_ConsentCheckbox> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => context.push('/legal/${LegalDocType.terms.slug}');
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => context.push('/legal/${LegalDocType.privacy.slug}');
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onChanged(!widget.accepted),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: widget.accepted,
              onChanged: (v) => widget.onChanged(v ?? false),
              activeColor: EsepColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: EsepColors.textSecondary,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(text: 'Согласен с '),
                      TextSpan(
                        text: 'Условиями',
                        style: const TextStyle(
                          color: EsepColors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _termsRecognizer,
                      ),
                      const TextSpan(text: ' и '),
                      TextSpan(
                        text: 'Политикой',
                        style: const TextStyle(
                          color: EsepColors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _privacyRecognizer,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Help-request dialog: пользователь не может войти ────────────────────────
// Отправляет запрос на /api/auth/help-request, админ получает уведомление в TG.

class _HelpRequestDialog extends StatefulWidget {
  const _HelpRequestDialog({required this.initialEmail});
  final String initialEmail;

  @override
  State<_HelpRequestDialog> createState() => _HelpRequestDialogState();
}

class _HelpRequestDialogState extends State<_HelpRequestDialog> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _msgCtrl;
  bool _loading = false;
  String? _error;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _phoneCtrl = TextEditingController();
    _msgCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Укажите корректный email');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/auth/help-request', {
        'email': email,
        'phone': _phoneCtrl.text.trim(),
        'message': _msgCtrl.text.trim(),
      });
      if (mounted) {
        setState(() {
          _sent = true;
          _loading = false;
        });
      }
      // Поглощаем неиспользуемый результат, но логируем для отладки
      // ignore: avoid_print
      print('help-request ok: $res');
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Нет соединения. Напишите в WhatsApp на +7 707 588 46 51';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: _sent ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EsepColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.key, color: EsepColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Восстановить доступ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Опишите проблему — мы свяжемся с вами в течение часа в рабочее время и поможем восстановить доступ.',
          style: TextStyle(
            fontSize: 13.5,
            color: EsepColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: EsepColors.expense.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: EsepColors.expense, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(color: EsepColors.expense, fontSize: 12.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
        ],

        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email *',
            hintText: 'name@example.com',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Телефон / WhatsApp (необязательно)',
            hintText: '+7 777 123 45 67',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _msgCtrl,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Что произошло (необязательно)',
            hintText: 'Например: забыл пароль, не получаю код, и т.п.',
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white,
                    ),
                  )
                : const Text('Отправить запрос'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EsepColors.income.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: EsepColors.income,
            size: 48,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Запрос отправлен',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          'Мы свяжемся с вами в течение часа в рабочее время. '
          'Проверьте Telegram, WhatsApp и email.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: EsepColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Понятно',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
