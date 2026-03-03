import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/theme/app_theme.dart';
import '../../core/providers/user_mode_provider.dart';

class MainScaffold extends ConsumerWidget {
  const MainScaffold({super.key, required this.child});
  final Widget child;

  // ── Tabs: ИП mode ─────────────────────────────────────────────────────────
  static const _ipTabs = [
    _TabItem(path: '/dashboard',    icon: Iconsax.home_2,     label: 'Главная'),
    _TabItem(path: '/invoices',     icon: Iconsax.receipt_2,  label: 'Счета'),
    _TabItem(path: '/transactions', icon: Iconsax.wallet_2,   label: 'Учёт'),
    _TabItem(path: '/taxes',        icon: Iconsax.calculator, label: 'Налоги'),
    _TabItem(path: '/clients',      icon: Iconsax.people,     label: 'Клиенты'),
  ];

  // ── Tabs: Бухгалтер mode ──────────────────────────────────────────────────
  static const _accountantTabs = [
    _TabItem(path: '/accountant',          icon: Iconsax.briefcase,   label: 'Клиенты'),
    _TabItem(path: '/accountant/calendar', icon: Iconsax.calendar_1,  label: 'Дедлайны'),
    _TabItem(path: '/taxes',               icon: Iconsax.calculator,  label: 'Расчёты'),
    _TabItem(path: '/settings',            icon: Iconsax.setting_2,   label: 'Настройки'),
  ];

  int _currentIndex(BuildContext context, List<_TabItem> tabs) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = tabs.indexWhere((t) => location.startsWith(t.path));
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(userModeProvider) ?? UserMode.ip;
    final tabs = mode == UserMode.accountant ? _accountantTabs : _ipTabs;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: EsepColors.divider, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex(context, tabs),
          onTap: (i) => context.go(tabs[i].path),
          items: tabs
              .map((t) => BottomNavigationBarItem(icon: Icon(t.icon), label: t.label))
              .toList(),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({required this.path, required this.icon, required this.label});
  final String path;
  final IconData icon;
  final String label;
}
