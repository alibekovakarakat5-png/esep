import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Обёртка для авторизационных и онбординг-экранов.
///
/// На мобильном (<720 px ширина) — растягивается на весь экран.
/// На десктопе и планшете — центрированная карточка с max-width 480 px,
/// тенью и скруглёнными углами на сером фоне страницы.
///
/// Использование:
///   Scaffold(
///     body: ResponsiveFormShell(child: ...),
///   )
class ResponsiveFormShell extends StatelessWidget {
  const ResponsiveFormShell({
    super.key,
    required this.child,
    this.maxWidth = 480,
    this.maxHeight = 760,
    this.padding = const EdgeInsets.all(0),
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;

    if (!isWide) {
      // Мобильный — без обёртки, child на весь экран
      return SafeArea(child: Padding(padding: padding, child: child));
    }

    // Десктоп — карточка
    return Container(
      color: const Color(0xFFF5F6FA),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Маленький хелпер для светлого фона на десктопе.
/// Используется в Scaffold.backgroundColor.
Color responsivePageBg(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 720 ? const Color(0xFFF5F6FA) : Colors.white;
}

// Подавляем неиспользованный импорт, если ничего не понадобится из темы
// (оставляю на будущее).
// ignore: unused_element
const _kUseTheme = EsepColors.primary;
