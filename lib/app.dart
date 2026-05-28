import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/widgets/impersonation_banner.dart';

class EsepApp extends ConsumerWidget {
  const EsepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Esep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      // Оборачиваем весь UI в красный баннер impersonation
      // (показывается только если AuthService.isImpersonated() == true)
      builder: (context, child) =>
          ImpersonationBanner(child: child ?? const SizedBox()),
    );
  }
}
