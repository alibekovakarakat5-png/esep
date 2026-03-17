import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

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
  bool _loading = false;
  String? _error;

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
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).register(email, pass, name);
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              // Logo + title
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: EsepColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('Е', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Есеп', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Учёт для вашего бизнеса',
                style: TextStyle(color: EsepColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 40),
              TabBar(
                controller: _tabs,
                labelColor: EsepColors.primary,
                unselectedLabelColor: EsepColors.textSecondary,
                indicatorColor: EsepColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [Tab(text: 'Войти'), Tab(text: 'Регистрация')],
              ),
              const SizedBox(height: 24),
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
                    Expanded(child: Text(_error!, style: const TextStyle(color: EsepColors.expense, fontSize: 13))),
                  ]),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _LoginTab(emailCtrl: _emailCtrl, passCtrl: _passCtrl, loading: _loading, onLogin: _login),
                    _RegisterTab(nameCtrl: _nameCtrl, emailCtrl: _emailCtrl, passCtrl: _passCtrl, loading: _loading, onRegister: _register),
                  ],
                ),
              ),

              // ── Demo mode button ──────────────────────────────────────
              const Divider(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Iconsax.eye, size: 18),
                  label: const Text('Посмотреть без входа'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: EsepColors.primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    ref.read(authProvider.notifier).enterDemo();
                  },
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Демо-данные — без регистрации',
                  style: TextStyle(fontSize: 12, color: EsepColors.textDisabled),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
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
    return Column(
      children: [
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 16),
        TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль'),
          onSubmitted: (_) => onLogin()),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: loading ? null : onLogin,
            child: loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Войти'),
          ),
        ),
      ],
    );
  }
}

class _RegisterTab extends StatelessWidget {
  const _RegisterTab({required this.nameCtrl, required this.emailCtrl, required this.passCtrl, required this.loading, required this.onRegister});
  final TextEditingController nameCtrl, emailCtrl, passCtrl;
  final bool loading;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Имя / ИП Фамилия')),
        const SizedBox(height: 16),
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 16),
        TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль'),
          onSubmitted: (_) => onRegister()),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: loading ? null : onRegister,
            child: loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать аккаунт'),
          ),
        ),
      ],
    );
  }
}
