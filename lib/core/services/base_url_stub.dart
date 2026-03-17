import 'dart:io' show Platform;

String detectApiBase() {
  // На реальном устройстве/релизе → Railway production
  // На эмуляторе Android (10.0.2.2) или локальной отладке → localhost
  const prod = 'https://esep-production.up.railway.app/api';
  const local = 'http://localhost:3001/api';

  // В release-сборке всегда production
  const isRelease = bool.fromEnvironment('dart.vm.product');
  if (isRelease) return prod;

  // В debug: проверяем — если Android эмулятор, используем 10.0.2.2
  try {
    if (Platform.isAndroid) return 'http://10.0.2.2:3001/api';
  } catch (_) {}

  return local;
}
