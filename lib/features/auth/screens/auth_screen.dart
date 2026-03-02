import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
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
              // Tab switcher
              TabBar(
                controller: _tabs,
                labelColor: EsepColors.primary,
                unselectedLabelColor: EsepColors.textSecondary,
                indicatorColor: EsepColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [Tab(text: 'Войти'), Tab(text: 'Регистрация')],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [_LoginTab(emailCtrl: _emailCtrl, passCtrl: _passCtrl), _RegisterTab(nameCtrl: _nameCtrl, emailCtrl: _emailCtrl, passCtrl: _passCtrl)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginTab extends StatelessWidget {
  const _LoginTab({required this.emailCtrl, required this.passCtrl});
  final TextEditingController emailCtrl, passCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 16),
        TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/dashboard'),
          child: const Text('Войти'),
        ),
      ],
    );
  }
}

class _RegisterTab extends StatelessWidget {
  const _RegisterTab({required this.nameCtrl, required this.emailCtrl, required this.passCtrl});
  final TextEditingController nameCtrl, emailCtrl, passCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Имя / ИП Фамилия')),
        const SizedBox(height: 16),
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 16),
        TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/dashboard'),
          child: const Text('Создать аккаунт'),
        ),
      ],
    );
  }
}
