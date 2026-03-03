import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

/// Результат парсинга одной строки выписки Kaspi
class KaspiRow {
  final DateTime date;
  final double amount;    // положительный = доход, отрицательный = расход
  final String description;
  final String? counterparty;
  final double? balance;
  bool isIncome;          // можно менять вручную в UI
  bool selected;          // выбрана для импорта

  KaspiRow({
    required this.date,
    required this.amount,
    required this.description,
    this.counterparty,
    this.balance,
    required this.isIncome,
    this.selected = true,
  });
}

/// Результат парсинга всего файла
class KaspiParseResult {
  final List<KaspiRow> rows;
  final String? accountNumber;
  final String format; // 'kaspi_gold', 'kaspi_business', 'generic'
  final List<String> warnings;

  const KaspiParseResult({
    required this.rows,
    this.accountNumber,
    required this.format,
    this.warnings = const [],
  });

  int get incomeCount => rows.where((r) => r.isIncome && r.selected).length;
  int get expenseCount => rows.where((r) => !r.isIncome && r.selected).length;
  double get totalIncome => rows
      .where((r) => r.isIncome && r.selected)
      .fold(0, (s, r) => s + r.amount.abs());
  double get totalExpense => rows
      .where((r) => !r.isIncome && r.selected)
      .fold(0, (s, r) => s + r.amount.abs());
}

class KaspiParser {
  KaspiParser._();

  static KaspiParseResult parse(List<int> bytes) {
    // Попытка декодировать как UTF-8, затем как Windows-1251
    String content;
    try {
      content = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      // Windows-1251 fallback — заменяем типичные символы
      content = latin1.decode(bytes);
    }

    // Убираем BOM если есть
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    // Убираем \r
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Определяем разделитель
    final delimiter = _detectDelimiter(content);

    // Парсим CSV
    final csvConverter = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
    );

    final allRows = csvConverter.convert(content);
    if (allRows.isEmpty) {
      return const KaspiParseResult(rows: [], format: 'unknown', warnings: ['Файл пустой']);
    }

    // Находим строку с заголовками
    int headerIndex = -1;
    Map<String, int> colMap = {};
    String format = 'generic';

    for (int i = 0; i < allRows.length && i < 10; i++) {
      final row = allRows[i].map((e) => e.toString().trim().toLowerCase()).toList();
      final detected = _detectFormat(row);
      if (detected != null) {
        headerIndex = i;
        colMap = detected['cols'] as Map<String, int>;
        format = detected['format'] as String;
        break;
      }
    }

    if (headerIndex == -1) {
      // Пытаемся угадать по позиции
      final result = _parseFallback(allRows);
      return result;
    }

    final warnings = <String>[];
    final rows = <KaspiRow>[];

    for (int i = headerIndex + 1; i < allRows.length; i++) {
      final rawRow = allRows[i];
      if (rawRow.isEmpty || rawRow.every((e) => e.toString().trim().isEmpty)) continue;

      final row = rawRow.map((e) => e.toString().trim()).toList();

      try {
        final parsed = _parseRow(row, colMap, format);
        if (parsed != null) rows.add(parsed);
      } catch (e) {
        warnings.add('Строка ${i + 1} пропущена: $e');
      }
    }

    return KaspiParseResult(
      rows: rows,
      format: format,
      warnings: warnings,
    );
  }

  static String _detectDelimiter(String content) {
    final firstLine = content.split('\n').first;
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    final tabs = '\t'.allMatches(firstLine).length;
    if (tabs > semicolons && tabs > commas) return '\t';
    if (semicolons >= commas) return ';';
    return ',';
  }

  static Map<String, dynamic>? _detectFormat(List<String> headerRow) {
    // Приводим к нижнему регистру для сравнения
    bool has(String s) => headerRow.any((h) => h.contains(s));
    int idx(String s) => headerRow.indexWhere((h) => h.contains(s));

    // Kaspi Business
    if (has('дата операции') || has('назначение платежа')) {
      return {
        'format': 'kaspi_business',
        'cols': {
          'date': idx('дата операции') >= 0 ? idx('дата операции') : idx('дата'),
          'amount': idx('сумма'),
          'description': idx('назначение') >= 0 ? idx('назначение') : idx('описание'),
          'counterparty': idx('контрагент'),
          'balance': idx('остаток') >= 0 ? idx('остаток') : idx('баланс'),
        },
      };
    }

    // Kaspi Gold
    if (has('дата') && has('описание') && has('сумма')) {
      return {
        'format': 'kaspi_gold',
        'cols': {
          'date': idx('дата'),
          'description': idx('описание'),
          'amount': idx('сумма'),
          'counterparty': -1,
          'balance': idx('остаток') >= 0 ? idx('остаток') : idx('баланс'),
        },
      };
    }

    // Generic — дата + сумма присутствуют
    if (has('дата') && has('сумма')) {
      final descIdx = idx('описание') >= 0 ? idx('описание') : idx('назначение');
      return {
        'format': 'generic',
        'cols': {
          'date': idx('дата'),
          'amount': idx('сумма'),
          'description': descIdx,
          'counterparty': idx('контрагент'),
          'balance': idx('остаток') >= 0 ? idx('остаток') : idx('баланс'),
        },
      };
    }

    return null;
  }

  static KaspiRow? _parseRow(
      List<String> row, Map<String, int> cols, String format) {
    final dateIdx = cols['date'] ?? 0;
    final amountIdx = cols['amount'] ?? 2;
    final descIdx = cols['description'] ?? 1;
    final cpIdx = cols['counterparty'] ?? -1;
    final balIdx = cols['balance'] ?? -1;

    if (dateIdx >= row.length || amountIdx >= row.length) return null;

    final dateStr = row[dateIdx];
    final amountStr = row[amountIdx];

    if (dateStr.isEmpty || amountStr.isEmpty) return null;

    final date = _parseDate(dateStr);
    if (date == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null) return null;

    final description = descIdx >= 0 && descIdx < row.length
        ? row[descIdx].isEmpty ? 'Без описания' : row[descIdx]
        : 'Импорт Kaspi';

    final counterparty = cpIdx >= 0 && cpIdx < row.length && row[cpIdx].isNotEmpty
        ? row[cpIdx]
        : null;

    final balance = balIdx >= 0 && balIdx < row.length
        ? _parseAmount(row[balIdx])
        : null;

    return KaspiRow(
      date: date,
      amount: amount.abs(),
      description: description,
      counterparty: counterparty,
      balance: balance,
      isIncome: amount > 0,
    );
  }

  /// Fallback — пытаемся угадать колонки по типу данных
  static KaspiParseResult _parseFallback(List<List<dynamic>> allRows) {
    final rows = <KaspiRow>[];
    for (final rawRow in allRows) {
      final row = rawRow.map((e) => e.toString().trim()).toList();
      if (row.length < 2) continue;

      DateTime? date;
      double? amount;
      String description = '';

      for (final cell in row) {
        date ??= _parseDate(cell);
        if (amount == null && cell.isNotEmpty) amount = _parseAmount(cell);
        if (description.isEmpty && cell.length > 3 && _parseDate(cell) == null && _parseAmount(cell) == null) {
          description = cell;
        }
      }

      if (date != null && amount != null) {
        rows.add(KaspiRow(
          date: date,
          amount: amount.abs(),
          description: description.isEmpty ? 'Импорт' : description,
          isIncome: amount > 0,
        ));
      }
    }

    return KaspiParseResult(
      rows: rows,
      format: 'generic',
      warnings: rows.isEmpty ? ['Не удалось распознать формат файла'] : [],
    );
  }

  static DateTime? _parseDate(String s) {
    // Форматы: dd.MM.yyyy HH:mm:ss | dd.MM.yyyy | dd/MM/yyyy | yyyy-MM-dd
    final patterns = [
      DateFormat('dd.MM.yyyy HH:mm:ss'),
      DateFormat('dd.MM.yyyy HH:mm'),
      DateFormat('dd.MM.yyyy'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('yyyy-MM-dd'),
    ];

    for (final fmt in patterns) {
      try {
        return fmt.parseStrict(s.trim());
      } catch (_) {}
    }
    return null;
  }

  static double? _parseAmount(String s) {
    if (s.isEmpty) return null;

    // Убираем символы: пробелы (тысячные), валюту, скобки
    var cleaned = s
        .replaceAll('\u00A0', '') // неразрывный пробел
        .replaceAll(' ', '')
        .replaceAll('₸', '')
        .replaceAll('KZT', '')
        .replaceAll('тг', '')
        .trim();

    // Скобки означают отрицательное число: (1500) -> -1500
    if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      cleaned = '-${cleaned.substring(1, cleaned.length - 1)}';
    }

    // Русский формат: запятая = десятичная, точка = тысячная
    // Определяем: если последний разделитель — запятая и после неё 2 цифры
    final commaIdx = cleaned.lastIndexOf(',');
    final dotIdx = cleaned.lastIndexOf('.');

    if (commaIdx > dotIdx) {
      // Запятая — десятичный разделитель
      cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
    } else if (dotIdx > commaIdx) {
      // Точка — десятичный разделитель
      cleaned = cleaned.replaceAll(',', '');
    }

    return double.tryParse(cleaned);
  }

  /// Авто-определение категории по описанию
  static String autoCategory(String description, bool isIncome) {
    final d = description.toLowerCase();

    if (isIncome) {
      if (d.contains('оплата') || d.contains('payment')) return 'Оплата услуг';
      if (d.contains('перевод') || d.contains('transfer')) return 'Перевод';
      if (d.contains('возврат') || d.contains('refund')) return 'Возврат';
      return 'Доход';
    } else {
      if (d.contains('налог') || d.contains('tax')) return 'Налоги';
      if (d.contains('аренда') || d.contains('rent')) return 'Аренда';
      if (d.contains('зарплата') || d.contains('salary')) return 'Зарплата';
      if (d.contains('коммунал') || d.contains('комуслуги')) return 'Коммунальные';
      if (d.contains('интернет') || d.contains('мобильный') || d.contains('телефон')) return 'Связь';
      if (d.contains('реклама') || d.contains('маркетинг')) return 'Реклама';
      if (d.contains('транспорт') || d.contains('такси') || d.contains('яндекс')) return 'Транспорт';
      if (d.contains('канцеляр') || d.contains('офис')) return 'Офис';
      return 'Прочее';
    }
  }
}
