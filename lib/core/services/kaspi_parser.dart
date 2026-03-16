import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
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

  /// Точка входа: определяет формат файла по расширению
  static KaspiParseResult parseFile(List<int> bytes, String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    if (ext == 'xlsx' || ext == 'xls') {
      return parseExcel(Uint8List.fromList(bytes));
    }
    return parseCsv(bytes);
  }

  /// Парсинг Excel (.xlsx) — основной формат Kaspi Business
  static KaspiParseResult parseExcel(Uint8List bytes) {
    final excel = xl.Excel.decodeBytes(bytes);
    final warnings = <String>[];

    // Берём первый лист
    if (excel.tables.isEmpty) {
      return const KaspiParseResult(rows: [], format: 'unknown', warnings: ['Файл не содержит листов']);
    }
    final sheet = excel.tables[excel.tables.keys.first]!;
    final allRows = sheet.rows;
    if (allRows.isEmpty) {
      return const KaspiParseResult(rows: [], format: 'unknown', warnings: ['Лист пустой']);
    }

    // Ищем заголовки в первых 10 строках
    int headerIndex = -1;
    Map<String, int> colMap = {};
    String format = 'generic';

    for (int i = 0; i < allRows.length && i < 10; i++) {
      final row = allRows[i].map((c) => (c?.value?.toString() ?? '').trim().toLowerCase()).toList();
      final detected = _detectFormat(row);
      if (detected != null) {
        headerIndex = i;
        colMap = detected['cols'] as Map<String, int>;
        format = detected['format'] as String;
        break;
      }
    }

    if (headerIndex == -1) {
      return const KaspiParseResult(rows: [], format: 'unknown', warnings: ['Не удалось найти заголовки']);
    }

    final rows = <KaspiRow>[];
    for (int i = headerIndex + 1; i < allRows.length; i++) {
      final rawRow = allRows[i];
      final row = rawRow.map((c) {
        final val = c?.value;
        // Excel может хранить дату как DateCellValue
        if (val is xl.DateCellValue) {
          return '${val.day.toString().padLeft(2, '0')}.${val.month.toString().padLeft(2, '0')}.${val.year}';
        }
        if (val is xl.DateTimeCellValue) {
          return '${val.day.toString().padLeft(2, '0')}.${val.month.toString().padLeft(2, '0')}.${val.year}';
        }
        return (val?.toString() ?? '').trim();
      }).toList();

      if (row.every((e) => e.isEmpty)) continue;

      try {
        final parsed = _parseRow(row, colMap, format);
        if (parsed != null) rows.add(parsed);
      } catch (e) {
        warnings.add('Строка ${i + 1} пропущена: $e');
      }
    }

    return KaspiParseResult(rows: rows, format: format, warnings: warnings);
  }

  /// Обратная совместимость
  static KaspiParseResult parse(List<int> bytes) => parseCsv(bytes);

  /// Парсинг CSV/TXT
  static KaspiParseResult parseCsv(List<int> bytes) {
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
    bool has(String s) => headerRow.any((h) => h.contains(s));
    int idx(String s) => headerRow.indexWhere((h) => h.contains(s));

    // Kaspi Business — с отдельными колонками Дебет/Кредит
    if (has('дата операции') || has('назначение платежа')) {
      final hasDebitCredit = has('дебет') && has('кредит');
      return {
        'format': 'kaspi_business',
        'cols': {
          'date': idx('дата операции') >= 0 ? idx('дата операции') : idx('дата'),
          'amount': hasDebitCredit ? -1 : idx('сумма'),
          'debit': idx('дебет'),     // расход
          'credit': idx('кредит'),   // приход
          'description': idx('назначение') >= 0 ? idx('назначение') : idx('описание'),
          'counterparty': idx('контрагент') >= 0 ? idx('контрагент') : idx('получатель'),
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
          'debit': -1,
          'credit': -1,
          'counterparty': -1,
          'balance': idx('остаток') >= 0 ? idx('остаток') : idx('баланс'),
        },
      };
    }

    // Halyk / Forte / Generic — дебет+кредит или сумма
    if (has('дата')) {
      final hasDebitCredit = has('дебет') && has('кредит');
      final hasAmount = has('сумма');
      if (!hasDebitCredit && !hasAmount) return null;

      final descIdx = idx('описание') >= 0
          ? idx('описание')
          : idx('назначение') >= 0
              ? idx('назначение')
              : idx('детали');
      return {
        'format': 'generic',
        'cols': {
          'date': idx('дата'),
          'amount': hasDebitCredit ? -1 : idx('сумма'),
          'debit': idx('дебет'),
          'credit': idx('кредит'),
          'description': descIdx,
          'counterparty': idx('контрагент') >= 0 ? idx('контрагент') : idx('получатель'),
          'balance': idx('остаток') >= 0 ? idx('остаток') : idx('баланс'),
        },
      };
    }

    return null;
  }

  static KaspiRow? _parseRow(
      List<String> row, Map<String, int> cols, String format) {
    final dateIdx = cols['date'] ?? 0;
    final amountIdx = cols['amount'] ?? -1;
    final debitIdx = cols['debit'] ?? -1;
    final creditIdx = cols['credit'] ?? -1;
    final descIdx = cols['description'] ?? 1;
    final cpIdx = cols['counterparty'] ?? -1;
    final balIdx = cols['balance'] ?? -1;

    if (dateIdx >= row.length) return null;

    final dateStr = row[dateIdx];
    if (dateStr.isEmpty) return null;

    final date = _parseDate(dateStr);
    if (date == null) return null;

    // Определяем сумму и направление
    double? amount;
    bool isIncome = false;

    if (debitIdx >= 0 && creditIdx >= 0 && debitIdx < row.length && creditIdx < row.length) {
      // Отдельные колонки Дебет (расход) и Кредит (приход)
      final debit = _parseAmount(row[debitIdx]);
      final credit = _parseAmount(row[creditIdx]);
      if (credit != null && credit > 0) {
        amount = credit;
        isIncome = true;
      } else if (debit != null && debit > 0) {
        amount = debit;
        isIncome = false;
      } else {
        return null; // обе колонки пустые
      }
    } else if (amountIdx >= 0 && amountIdx < row.length) {
      // Одна колонка Сумма (положительная = доход, отрицательная = расход)
      final parsed = _parseAmount(row[amountIdx]);
      if (parsed == null) return null;
      amount = parsed.abs();
      isIncome = parsed > 0;
    } else {
      return null;
    }

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
      amount: amount,
      description: description,
      counterparty: counterparty,
      balance: balance,
      isIncome: isIncome,
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
