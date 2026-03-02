import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/theme/app_theme.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    _TabItem(path: '/dashboard',    icon: Iconsax.home_2,    label: 'Главная'),
    _TabItem(path: '/invoices',     icon: Iconsax.receipt_2, label: 'Счета'),
    _TabItem(path: '/transactions', icon: Iconsax.wallet_2,  label: 'Учёт'),
    _TabItem(path: '/taxes',        icon: Iconsax.calculator,label: 'Налоги'),
    _TabItem(path: '/clients',      icon: Iconsax.people,    label: 'Клиенты'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: EsepColors.divider, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex(context),
          onTap: (i) => context.go(_tabs[i].path),
          items: _tabs
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
