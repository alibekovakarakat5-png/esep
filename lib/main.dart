import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/services/hive_service.dart';
import 'core/services/category_memory.dart';
import 'core/services/notification_service.dart';
import 'core/services/tax_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await HiveService.init();
  await CategoryMemory.init();

  // Загрузить налоговый конфиг из кэша (Hive)
  await TaxConfigService.init();
  // Обновить с сервера (не блокирует UI, fallback на кэш/хардкод)
  TaxConfigService.fetch();

  // Проверяем дедлайны и показываем уведомления (если разрешены)
  NotificationService.checkDeadlines();

  runApp(
    const ProviderScope(
      child: EsepApp(),
    ),
  );
}
