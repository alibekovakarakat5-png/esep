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
  String? category;       // категория (авто или ручная)

  KaspiRow({
    required this.date,
    required this.amount,
    required this.description,
    this.counterparty,
    this.balance,
    required this.isIncome,
    this.selected = true,
    this.category,
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

  // ── Словари заголовков (рус / каз / англ) ───────────────────────────
  // Сопоставление по contains в нижнем регистре, поэтому хватает корней.
  static const _dateWords = ['дата', 'күні', 'кунi', 'куні', 'date', 'мерзім'];
  static const _amountWords = ['сумма', 'сома', 'сомасы', 'amount', 'сумм'];
  static const _debitWords = ['дебет', 'debit', 'расход', 'шығыс', 'списание', 'шыгыс'];
  static const _creditWords = [
    'кредит', 'credit', 'приход', 'кіріс', 'кiрiс', 'түсім', 'тусим',
    'зачисление', 'поступление'
  ];
  static const _descWords = [
    'описание', 'назначение', 'детали', 'сипаттама', 'description', 'details',
    'мақсат', 'максат', 'операция', 'комментарий', 'примечание', 'purpose'
  ];
  static const _cpWords = [
    'контрагент', 'получатель', 'отправитель', 'қарсы', 'карсы', 'бенефициар',
    'плательщик', 'корреспондент'
  ];
  static const _balWords = ['остаток', 'баланс', 'қалдық', 'калдык', 'balance'];

  static int _findCol(List<String> row, List<String> words) =>
      row.indexWhere((h) => words.any((w) => h.contains(w)));

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
    final xl.Excel excel;
    try {
      excel = xl.Excel.decodeBytes(bytes);
    } catch (e) {
      return KaspiParseResult(
        rows: const [],
        format: 'unknown',
        warnings: ['Не удалось открыть Excel-файл. Возможно это старый формат .xls — '
            'пересохраните как .xlsx или скачайте выписку в CSV. ($e)'],
      );
    }

    if (excel.tables.isEmpty) {
      return const KaspiParseResult(
          rows: [], format: 'unknown', warnings: ['Файл не содержит листов']);
    }
    final sheet = excel.tables[excel.tables.keys.first]!;
    if (sheet.rows.isEmpty) {
      return const KaspiParseResult(
          rows: [], format: 'unknown', warnings: ['Лист пустой']);
    }

    // Приводим лист к матрице строк; даты Excel нормализуем в dd.MM.yyyy.
    final matrix = sheet.rows.map((r) {
      return r.map((c) {
        final val = c?.value;
        if (val is xl.DateCellValue) {
          return '${val.day.toString().padLeft(2, '0')}.'
              '${val.month.toString().padLeft(2, '0')}.${val.year}';
        }
        if (val is xl.DateTimeCellValue) {
          return '${val.day.toString().padLeft(2, '0')}.'
              '${val.month.toString().padLeft(2, '0')}.${val.year}';
        }
        return (val?.toString() ?? '').trim();
      }).toList();
    }).toList();

    return _parseMatrix(matrix);
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
      content = latin1.decode(bytes);
    }

    // Убираем BOM если есть
    if (content.startsWith('﻿')) {
      content = content.substring(1);
    }

    // Нормализуем переводы строк
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final delimiter = _detectDelimiter(content);

    final csvConverter = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
    );

    final allRows = csvConverter.convert(content);
    if (allRows.isEmpty) {
      return const KaspiParseResult(
          rows: [], format: 'unknown', warnings: ['Файл пустой']);
    }

    final matrix =
        allRows.map((r) => r.map((e) => e.toString()).toList()).toList();
    return _parseMatrix(matrix);
  }

  /// Общий разбор матрицы строк (после Excel/CSV). Сначала ищет шапку
  /// (рус/каз/англ) в первых 25 строках; если не нашёл или по шапке
  /// ничего не вышло — разбирает по содержимому колонок.
  static KaspiParseResult _parseMatrix(List<List<String>> allRows) {
    int headerIndex = -1;
    Map<String, int> colMap = {};
    String format = 'generic';

    final scan = allRows.length < 25 ? allRows.length : 25;
    for (int i = 0; i < scan; i++) {
      final row = allRows[i].map((e) => e.trim().toLowerCase()).toList();
      final detected = _detectFormat(row);
      if (detected != null) {
        headerIndex = i;
        colMap = detected['cols'] as Map<String, int>;
        format = detected['format'] as String;
        break;
      }
    }

    if (headerIndex == -1) {
      // Шапку не распознали — пробуем по содержимому.
      return _parseByContent(allRows);
    }

    final warnings = <String>[];
    final rows = <KaspiRow>[];
    for (int i = headerIndex + 1; i < allRows.length; i++) {
      final row = allRows[i].map((e) => e.trim()).toList();
      if (row.every((e) => e.isEmpty)) continue;
      try {
        final parsed = _parseRow(row, colMap, format);
        if (parsed != null) rows.add(parsed);
      } catch (e) {
        warnings.add('Строка ${i + 1} пропущена: $e');
      }
    }

    // Шапку нашли, но строк ноль — даём шанс разбору по содержимому.
    if (rows.isEmpty) {
      final fb = _parseByContent(allRows);
      if (fb.rows.isNotEmpty) return fb;
    }

    return KaspiParseResult(rows: rows, format: format, warnings: warnings);
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

  /// Распознаёт шапку выписки по ключевым словам (рус/каз/англ).
  /// Строка считается шапкой, если есть колонка даты И (дебет+кредит ИЛИ сумма).
  static Map<String, dynamic>? _detectFormat(List<String> headerRow) {
    final dateIdx = _findCol(headerRow, _dateWords);
    if (dateIdx < 0) return null;

    final debitIdx = _findCol(headerRow, _debitWords);
    final creditIdx = _findCol(headerRow, _creditWords);
    final amountIdx = _findCol(headerRow, _amountWords);
    final hasDebitCredit = debitIdx >= 0 && creditIdx >= 0;

    if (!hasDebitCredit && amountIdx < 0) return null;

    final descIdx = _findCol(headerRow, _descWords);
    final cpIdx = _findCol(headerRow, _cpWords);
    final balIdx = _findCol(headerRow, _balWords);

    return {
      'format': hasDebitCredit ? 'kaspi_business' : 'generic',
      'cols': {
        'date': dateIdx,
        'amount': hasDebitCredit ? -1 : amountIdx,
        'debit': debitIdx,
        'credit': creditIdx,
        'description': descIdx,
        'counterparty': cpIdx,
        'balance': balIdx,
      },
    };
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

    double? amount;
    bool isIncome = false;

    if (debitIdx >= 0 &&
        creditIdx >= 0 &&
        debitIdx < row.length &&
        creditIdx < row.length) {
      final debit = _parseAmount(row[debitIdx]);
      final credit = _parseAmount(row[creditIdx]);
      if (credit != null && credit.abs() > 0) {
        amount = credit.abs();
        isIncome = true;
      } else if (debit != null && debit.abs() > 0) {
        amount = debit.abs();
        isIncome = false;
      } else {
        return null;
      }
    } else if (amountIdx >= 0 && amountIdx < row.length) {
      final parsed = _parseAmount(row[amountIdx]);
      if (parsed == null) return null;
      amount = parsed.abs();
      isIncome = parsed > 0;
    } else {
      return null;
    }

    final description = descIdx >= 0 && descIdx < row.length
        ? row[descIdx].isEmpty
            ? 'Без описания'
            : row[descIdx]
        : 'Импорт выписки';

    final counterparty =
        cpIdx >= 0 && cpIdx < row.length && row[cpIdx].isNotEmpty
            ? row[cpIdx]
            : null;

    final balance =
        balIdx >= 0 && balIdx < row.length ? _parseAmount(row[balIdx]) : null;

    return KaspiRow(
      date: date,
      amount: amount,
      description: description,
      counterparty: counterparty,
      balance: balance,
      isIncome: isIncome,
    );
  }

  /// Запасной разбор: шапку не нашли — определяем колонки по содержимому.
  /// Колонка даты = где больше всего распознанных дат; колонка суммы =
  /// со знаком «минус» (если есть) либо самая «числовая»; описание = колонка
  /// с самым длинным текстом.
  static KaspiParseResult _parseByContent(List<List<String>> allRows) {
    int ncol = 0;
    for (final r in allRows) {
      if (r.length > ncol) ncol = r.length;
    }
    if (ncol == 0) {
      return const KaspiParseResult(
          rows: [],
          format: 'unknown',
          warnings: ['Не удалось распознать формат файла']);
    }

    final dateHits = List<int>.filled(ncol, 0);
    final numHits = List<int>.filled(ncol, 0);
    final negHits = List<int>.filled(ncol, 0);
    final textLen = List<int>.filled(ncol, 0);

    for (final row in allRows) {
      for (int c = 0; c < row.length; c++) {
        final cell = row[c].trim();
        if (cell.isEmpty) continue;
        if (_parseDate(cell) != null) {
          dateHits[c]++;
          continue;
        }
        final amt = _parseAmount(cell);
        if (amt != null) {
          numHits[c]++;
          if (amt < 0) negHits[c]++;
        } else {
          textLen[c] += cell.length;
        }
      }
    }

    int argmax(List<int> a, {int exclude = -1}) {
      int best = -1, bestV = 0;
      for (int c = 0; c < a.length; c++) {
        if (c == exclude) continue;
        if (a[c] > bestV) {
          bestV = a[c];
          best = c;
        }
      }
      return best;
    }

    final dateCol = argmax(dateHits);
    if (dateCol < 0 || dateHits[dateCol] < 2) {
      return const KaspiParseResult(
          rows: [],
          format: 'unknown',
          warnings: ['Не удалось распознать формат файла (не найдены даты)']);
    }

    // Предпочитаем колонку со знаковыми суммами (есть отрицательные).
    int amountCol = argmax(negHits, exclude: dateCol);
    if (amountCol < 0 || negHits[amountCol] < 1) {
      amountCol = argmax(numHits, exclude: dateCol);
    }
    if (amountCol < 0 || numHits[amountCol] < 2) {
      return const KaspiParseResult(
          rows: [],
          format: 'unknown',
          warnings: ['Не удалось распознать формат файла (не найдены суммы)']);
    }

    final descCol = argmax(textLen, exclude: dateCol);

    final rows = <KaspiRow>[];
    for (final row in allRows) {
      if (dateCol >= row.length || amountCol >= row.length) continue;
      final date = _parseDate(row[dateCol].trim());
      if (date == null) continue;
      final amt = _parseAmount(row[amountCol].trim());
      if (amt == null) continue;
      final desc = (descCol >= 0 &&
              descCol < row.length &&
              row[descCol].trim().isNotEmpty)
          ? row[descCol].trim()
          : 'Импорт выписки';
      rows.add(KaspiRow(
        date: date,
        amount: amt.abs(),
        description: desc,
        isIncome: amt > 0,
      ));
    }

    return KaspiParseResult(
      rows: rows,
      format: 'generic',
      warnings: rows.isEmpty
          ? ['Не удалось распознать формат файла']
          : ['Формат распознан автоматически по содержимому — '
              'проверьте суммы и где доход/расход.'],
    );
  }

  static DateTime? _parseDate(String s) {
    final patterns = [
      DateFormat('dd.MM.yyyy HH:mm:ss'),
      DateFormat('dd.MM.yyyy HH:mm'),
      DateFormat('dd.MM.yyyy'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('dd-MM-yyyy'),
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('yyyy/MM/dd'),
    ];

    final t = s.trim();
    if (t.isEmpty) return null;
    for (final fmt in patterns) {
      try {
        return fmt.parseStrict(t);
      } catch (_) {}
    }
    return null;
  }

  static double? _parseAmount(String s) {
    if (s.isEmpty) return null;

    var cleaned = s
        .replaceAll(' ', '')
        .replaceAll(' ', '')
        .replaceAll('₸', '')
        .replaceAll('KZT', '')
        .replaceAll('kzt', '')
        .replaceAll('тг', '')
        .trim();

    if (cleaned.isEmpty) return null;

    // Скобки = отрицательное: (1500) -> -1500
    if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      cleaned = '-${cleaned.substring(1, cleaned.length - 1)}';
    }

    final commaIdx = cleaned.lastIndexOf(',');
    final dotIdx = cleaned.lastIndexOf('.');

    if (commaIdx > dotIdx) {
      cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
    } else if (dotIdx > commaIdx) {
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
