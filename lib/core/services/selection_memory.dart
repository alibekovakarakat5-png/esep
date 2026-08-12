import 'package:hive_flutter/hive_flutter.dart';

/// Память решений «бизнес/личное» при импорте выписки.
///
/// Пользователь один раз снял галочку с «Rancho магазин продуктов» — в
/// следующих выписках Esep снимет её сам; вернул галочку переводу от
/// клиента — тот навсегда отмечен. Память сильнее правил ImportAutoSelect.
/// Устройство повторяет CategoryMemory: Hive-бокс, ключи по контрагенту
/// (приоритет) и описанию.
class SelectionMemory {
  static const _boxName = 'selection_memory';

  static Future<void> remember(
      String description, String? counterparty, bool selected) async {
    final box = Hive.box(_boxName);
    if (counterparty != null && counterparty.isNotEmpty) {
      await box.put(_normalize(counterparty), selected);
    }
    final key = _normalize(description);
    if (key.isNotEmpty) {
      await box.put(key, selected);
    }
  }

  /// null — операция незнакома, пусть решают правила предвыбора.
  static bool? recall(String description, String? counterparty) {
    final box = Hive.box(_boxName);
    if (counterparty != null && counterparty.isNotEmpty) {
      final v = box.get(_normalize(counterparty));
      if (v != null) return v as bool;
    }
    return box.get(_normalize(description)) as bool?;
  }

  static String _normalize(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Initialize the box (call in main.dart)
  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }
}
