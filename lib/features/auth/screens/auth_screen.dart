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
import '../../../shared/widgets/responsive_form_shell.dart';

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
    if (name.isEmpty || email.isEmpty || pass.isEmpty) return;
    if (!_consentAccepted) {
      setState(() => _error =
          'Подтвердите согласие с условиями использования');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).register(email, pass, name);
      // Зафиксировать согласие с текущей версией документов
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
    return Scaffold(
      backgroundColor: responsivePageBg(context),
      body: ResponsiveFormShell(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo + title
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: EsepColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('E',
                      style: TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700,
                      )),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Esep',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Учёт для вашего бизнеса',
              style: TextStyle(color: EsepColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),
            TabBar(
              controller: _tabs,
              labelColor: EsepColors.primary,
              unselectedLabelColor: EsepColors.textSecondary,
              indicatorColor: EsepColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [Tab(text: 'Войти'), Tab(text: 'Регистрация')],
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: EsepColors.expense.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: EsepColors.expense, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: EsepColors.expense, fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _LoginTab(emailCtrl: _emailCtrl, passCtrl: _passCtrl,
                      loading: _loading, onLogin: _login),
                  _RegisterTab(
                    nameCtrl: _nameCtrl,
                    emailCtrl: _emailCtrl,
                    passCtrl: _passCtrl,
                    loading: _loading,
                    consentAccepted: _consentAccepted,
                    onConsentChanged: (v) => setState(() => _consentAccepted = v),
                    onRegister: _register,
                  ),
                ],
              ),
            ),

            // ── Demo mode button ──────────────────────────────────────
            const Divider(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Iconsax.eye, size: 18),
                label: const Text('Посмотреть без входа'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: EsepColors.primary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  ref.read(authProvider.notifier).enterDemo();
                },
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Демо-данные — без регистрации',
                style: TextStyle(fontSize: 12, color: EsepColors.textDisabled),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginTab extends StatelessWidget {
  const _LoginTab({required this.emailCtrl, required this.passCtrl, required this.loading, required this.onLogin});
  final TextEditingController emailCtrl, passCtrl;
  final bool loading;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Пароль'),
          onSubmitted: (_) => onLogin(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/forgot-password'),
            child: const Text('Забыли пароль?'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: loading ? null : onLogin,
            child: loading
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
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
    required this.loading,
    required this.consentAccepted,
    required this.onConsentChanged,
    required this.onRegister,
  });
  final TextEditingController nameCtrl, emailCtrl, passCtrl;
  final bool loading;
  final bool consentAccepted;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final canSubmit = consentAccepted && !loading;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Имя / ИП Фамилия')),
        const SizedBox(height: 16),
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 16),
        TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль'),
          onSubmitted: (_) { if (canSubmit) onRegister(); }),
        const SizedBox(height: 16),
        _ConsentCheckbox(
          accepted: consentAccepted,
          onChanged: onConsentChanged,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canSubmit ? onRegister : null,
            child: loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Создать аккаунт'),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Чекбокс с кликабельными ссылками на документы.
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
                      fontSize: 13,
                      color: EsepColors.textSecondary,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(text: 'Я ознакомлен(а) и согласен(а) с '),
                      TextSpan(
                        text: 'Условиями использования',
                        style: const TextStyle(
                          color: EsepColors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _termsRecognizer,
                      ),
                      const TextSpan(text: ' и '),
                      TextSpan(
                        text: 'Политикой конфиденциальности',
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
