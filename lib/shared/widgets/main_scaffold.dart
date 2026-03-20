import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/theme/app_theme.dart';
import '../../core/providers/user_mode_provider.dart';

/// Breakpoint: wider than this → sidebar, narrower → bottom nav.
const _kDesktopBreakpoint = 900.0;

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
    _TabItem(path: '/settings',     icon: Iconsax.setting_2,  label: 'Настройки'),
  ];

  // ── Tabs: ТОО mode ────────────────────────────────────────────────────────
  static const _tooTabs = [
    _TabItem(path: '/dashboard',    icon: Iconsax.home_2,     label: 'Главная'),
    _TabItem(path: '/invoices',     icon: Iconsax.receipt_2,  label: 'Счета'),
    _TabItem(path: '/transactions', icon: Iconsax.wallet_2,   label: 'Учёт'),
    _TabItem(path: '/taxes',        icon: Iconsax.calculator, label: 'Налоги'),
    _TabItem(path: '/clients',      icon: Iconsax.people,     label: 'Клиенты'),
    _TabItem(path: '/settings',     icon: Iconsax.setting_2,  label: 'Настройки'),
  ];

  // ── Tabs: Бухгалтер mode ──────────────────────────────────────────────────
  static const _accountantTabs = [
    _TabItem(path: '/accountant',          icon: Iconsax.briefcase,   label: 'Клиенты'),
    _TabItem(path: '/accountant/calendar', icon: Iconsax.calendar_1,  label: 'Дедлайны'),
    _TabItem(path: '/taxes',               icon: Iconsax.calculator,  label: 'Расчёты'),
    _TabItem(path: '/settings',            icon: Iconsax.setting_2,   label: 'Настройки'),
  ];

  List<_TabItem> _tabsForMode(UserMode mode) {
    switch (mode) {
      case UserMode.accountant:
        return _accountantTabs;
      case UserMode.too:
        return _tooTabs;
      case UserMode.ip:
        return _ipTabs;
    }
  }

  int _currentIndex(BuildContext context, List<_TabItem> tabs) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = tabs.indexWhere((t) => location.startsWith(t.path));
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(userModeProvider) ?? UserMode.ip;
    final tabs = _tabsForMode(mode);
    final isWide = MediaQuery.sizeOf(context).width >= _kDesktopBreakpoint;

    if (isWide) {
      return _DesktopLayout(tabs: tabs, currentIndex: _currentIndex(context, tabs), child: child);
    }

    // Mobile: bottom nav
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

// ═════════════════════════════════════════════════════════════════════════════
// Desktop layout: sidebar + centered content
// ═════════════════════════════════════════════════════════════════════════════

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.tabs, required this.currentIndex, required this.child});
  final List<_TabItem> tabs;
  final int currentIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────────
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1D23) : Colors.white,
              border: const Border(
                right: BorderSide(color: EsepColors.divider, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Logo
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: EsepColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Text('e', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Text('esep', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Nav items
                const SizedBox(height: 8),
                ...List.generate(tabs.length, (i) {
                  final tab = tabs[i];
                  final selected = i == currentIndex;
                  return _SidebarItem(
                    icon: tab.icon,
                    label: tab.label,
                    selected: selected,
                    onTap: () => context.go(tab.path),
                  );
                }),

                const Spacer(),

                // Version
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Esep v1.0', style: TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
                ),
              ],
            ),
          ),

          // ── Content ──────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? EsepColors.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? EsepColors.primary : EsepColors.textSecondary),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? EsepColors.primary : EsepColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
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
