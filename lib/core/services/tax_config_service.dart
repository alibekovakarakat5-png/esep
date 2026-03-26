import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'api_client.dart';

/// Сервис для загрузки налоговых констант с сервера.
/// Кэширует в Hive — работает офлайн с последними загруженными данными.
/// Если сервер недоступен и кэша нет — `KzTax` использует хардкод-fallback.
class TaxConfigService {
  TaxConfigService._();

  static const _boxName = 'tax_config';
  static const _cacheKey = 'remote_config';
  static const _lastFetchKey = 'last_fetch';

  /// Кэшированные значения (key → value string)
  static Map<String, String> _cache = {};

  /// Загружено ли что-то (из сети или Hive)
  static bool _loaded = false;
  static bool get isLoaded => _loaded;

  /// Инициализация: открыть Hive box + загрузить из кэша
  static Future<void> init() async {
    final box = await Hive.openBox(_boxName);
    final cached = box.get(_cacheKey);
    if (cached != null) {
      _cache = Map<String, String>.from(
        (jsonDecode(cached as String) as Map).map(
          (k, v) => MapEntry(k as String, v.toString()),
        ),
      );
      _loaded = true;
    }
  }

  /// Загрузить конфиг с сервера. Вызывать при запуске приложения.
  /// Не блокирует UI — если ошибка, используются Hive-кэш или хардкод.
  static Future<void> fetch() async {
    try {
      final data = await ApiClient.get('/api/config/tax');
      if (data is Map) {
        final newCache = <String, String>{};
        for (final entry in data.entries) {
          final v = entry.value;
          if (v is Map && v.containsKey('value')) {
            newCache[entry.key as String] = v['value'].toString();
          } else {
            newCache[entry.key as String] = v.toString();
          }
        }
        _cache = newCache;
        _loaded = true;

        // Сохранить в Hive
        final box = Hive.box(_boxName);
        await box.put(_cacheKey, jsonEncode(_cache));
        await box.put(_lastFetchKey, DateTime.now().toIso8601String());
      }
    } catch (e) {
      // Не страшно — используем кэш или хардкод
      // ignore: avoid_print
      print('[TaxConfig] fetch error (using cache): $e');
    }
  }

  /// Получить значение по ключу. Возвращает null если не найдено.
  static String? getString(String key) => _cache[key];

  /// Получить double по ключу, или fallback если нет.
  static double getDouble(String key, double fallback) {
    final s = _cache[key];
    if (s == null) return fallback;
    return double.tryParse(s) ?? fallback;
  }

  /// Получить int по ключу, или fallback если нет.
  static int getInt(String key, int fallback) {
    final s = _cache[key];
    if (s == null) return fallback;
    return int.tryParse(s) ?? fallback;
  }

  /// Когда последний раз загружали с сервера
  static DateTime? get lastFetch {
    try {
      final box = Hive.box(_boxName);
      final s = box.get(_lastFetchKey) as String?;
      return s != null ? DateTime.parse(s) : null;
    } catch (_) {
      return null;
    }
  }
}
