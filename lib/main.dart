import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/services/auth_service.dart';
import 'core/services/hive_service.dart';
import 'core/services/category_memory.dart';
import 'core/services/notification_service.dart';
import 'core/services/tax_config_service.dart';
import 'core/services/url_params_stub.dart'
    if (dart.library.html) 'core/services/url_params_web.dart'
    if (dart.library.js_interop) 'core/services/url_params_web.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await HiveService.init();
  await CategoryMemory.init();

  // Загрузить налоговый конфиг из кэша (Hive)
  await TaxConfigService.init();
  // Обновить с сервера (не блокирует UI, fallback на кэш/хардкод)
  TaxConfigService.fetch();

  // Если в URL передан токен impersonation (из админки) — принимаем его
  // ДО старта приложения, чтобы AuthNotifier сразу увидел сохранённый токен.
  final params = readUrlParams();
  final impToken = params['impersonate'];
  final impEmail = params['imp_email'];
  if (impToken != null && impToken.isNotEmpty) {
    await AuthService.acceptImpersonationToken(
      impToken, impEmail ?? 'unknown',
    );
    clearUrlParams(['impersonate', 'imp_email']);
  }

  // Проверяем дедлайны и показываем уведомления (если разрешены)
  NotificationService.checkDeadlines();

  runApp(
    const ProviderScope(
      child: EsepApp(),
    ),
  );
}
