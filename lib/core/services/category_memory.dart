import 'package:hive_flutter/hive_flutter.dart';

/// Запоминает категории по контрагенту/описанию.
/// Следующий импорт автоматически подставит.
class CategoryMemory {
  static const _boxName = 'category_memory';

  /// Все категории для импорта
  static const List<String> allCategories = [
    'Доход',
    'Оплата услуг',
    'Перевод',
    'Возврат',
    'Налоги',
    'Аренда',
    'Зарплата',
    'Коммунальные',
    'Связь',
    'Реклама',
    'Транспорт',
    'Офис',
    'Прочее',
  ];

  /// Save mapping: normalized key -> category
  static Future<void> remember(
      String description, String? counterparty, String category) async {
    final box = Hive.box(_boxName);
    // Save by counterparty (higher priority)
    if (counterparty != null && counterparty.isNotEmpty) {
      await box.put(_normalize(counterparty), category);
    }
    // Also save by description keywords
    final key = _normalize(description);
    if (key.isNotEmpty) {
      await box.put(key, category);
    }
  }

  /// Lookup: try counterparty first, then description
  static String? recall(String description, String? counterparty) {
    final box = Hive.box(_boxName);
    if (counterparty != null && counterparty.isNotEmpty) {
      final cat = box.get(_normalize(counterparty));
      if (cat != null) return cat as String;
    }
    return box.get(_normalize(description)) as String?;
  }

  static String _normalize(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Initialize the box (call in main.dart)
  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }
}
