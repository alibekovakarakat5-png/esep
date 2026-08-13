import 'kaspi_parser.dart';

/// Умный предвыбор галочек при импорте PDF-выписки Kaspi Gold.
///
/// Личная карта — бизнес и быт вперемешку; снимать сотни галочек руками
/// нельзя. Правила выведены из реальной годовой выписки (1429 операций):
/// они агрессивно прячут «похожее на личное», а пользователь только
/// проверяет остаток. Память решений (SelectionMemory) сильнее правил.
///
/// Для Excel/CSV (operation == null) предвыбор не вмешивается — там
/// обычно рабочий счёт Kaspi Business, всё бизнесовое.
class ImportAutoSelect {
  /// Переводы до этой суммы считаем личной мелочью (проезд, кофе, свои).
  static const double smallTransferLimit = 5000;

  /// Доходные «Пополнения», которые на самом деле свои деньги — не выручка.
  static final RegExp _ownMoney =
      RegExp('карты другого банка|депозит|зарплата', caseSensitive: false);

  /// true — оставить галочку (похоже на бизнес), false — снять (личное).
  static bool suggest(KaspiRow row) {
    final op = row.operation;
    if (op == null) return true; // Excel/CSV — не вмешиваемся

    if (row.isIncome) {
      return !_ownMoney.hasMatch(row.description);
    }
    if (op == 'Покупка') return false;
    if (op == 'Перевод' && row.amount < smallTransferLimit) return false;
    return true;
  }
}
