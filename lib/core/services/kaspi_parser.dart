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
  final String format; // 'kaspi_gold', 'kaspi_business', 'generic', 'pdf', 'unknown'
  final List<String> warnings;

  /// Сырые строки файла — нужны для ручного сопоставления колонок,
  /// когда автоматическое распознавание не сработало.
  final List<List<String>> matrix;

  const KaspiParseResult({
    required this.rows,
    this.accountNumber,
    required this.format,
    this.warnings = const [],
    this.matrix = const [],
  });

  /// Можно ли предложить пользователю разметить колонки вручную:
  /// строк не распознали, но таблица в файле есть.
  bool get canMapManually => rows.isEmpty && matrix.length > 1;

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
  // Покрывают выписки Kaspi, Halyk, Forte, Jusan, БЦК (ЦентрКредит), Bereke,
  // Freedom, Altyn, Евразийского. Длинные слова ищутся подстрокой (корня
  // хватает), короткие (≤3 симв., напр. «дт»/«кт») — только по границам слова:
  // иначе «фаКТура» ловится как кредит, а «доКумент»/«креДиТ» дают ложные
  // срабатывания.
  static const _dateWords = [
    'дата', 'күні', 'кунi', 'куні', 'date', 'мерзім', 'мерзімі',
    'опер.день', 'операционный день', 'дата проводки', 'дата операции',
    'дата валютирования', 'дата документа',
  ];
  static const _amountWords = [
    'сумма', 'сома', 'сомасы', 'amount', 'сумм', 'оборот', 'сумма операции',
    'сумма в валюте', 'сумма платежа', 'мөлшер', 'молшер',
  ];
  // ВАЖНО: храним КОРНИ без окончаний — «Сумма списания» не содержит
  // подстроку «списание», но содержит «списан».
  static const _debitWords = [
    'дебет', 'debit', 'расход', 'шығыс', 'шыгыс', 'списан', 'снятие',
    'дт', 'дб', 'выдач', 'уменьшен', 'исходящ', 'outgoing', 'out',
    'төлем', 'тольем',
  ];
  static const _creditWords = [
    'кредит', 'credit', 'приход', 'кіріс', 'кiрiс', 'түсім', 'тусим',
    'зачислен', 'поступлен', 'пополнен',
    'кт', 'увеличен', 'входящ', 'incoming', 'in',
  ];
  static const _descWords = [
    'описан', 'назначен', 'детал', 'сипаттама', 'description', 'details',
    'мақсат', 'максат', 'операц', 'комментар', 'примечан', 'purpose',
    'содержан', 'реквизит',
  ];
  static const _cpWords = [
    'контрагент', 'получател', 'отправител', 'қарсы', 'карсы', 'бенефициар',
    'плательщ', 'корреспондент', 'наименован', 'клиент', 'партнер',
    'партнёр', 'counterparty', 'алушы',
  ];
  static const _balWords = [
    'остат', 'баланс', 'қалдық', 'калдык', 'balance', 'сальдо',
  ];

  /// True, если заголовок колонки соответствует одному из слов словаря.
  /// Короткие токены матчатся только целым словом (см. комментарий выше).
  static bool _headerMatches(String header, List<String> words) {
    final h = header.trim().toLowerCase();
    if (h.isEmpty) return false;
    for (final w in words) {
      if (w.length <= 3) {
        final re = RegExp('(^|[^0-9a-zа-яёәғқңөұүhі])'
            '${RegExp.escape(w)}'
            '([^0-9a-zа-яёәғқңөұүhі]|\$)');
        if (re.hasMatch(h)) return true;
      } else if (h.contains(w)) {
        return true;
      }
    }
    return false;
  }

  static int _findCol(List<String> row, List<String> words) =>
      row.indexWhere((h) => _headerMatches(h, words));

  /// Точка входа: определяет формат файла по расширению
  static KaspiParseResult parseFile(List<int> bytes, String fileName) {
    final ext = fileName.toLowerCase().split('.').last;

    // PDF пока не разбираем — но объясняем, где взять поддерживаемый файл,
    // вместо немого «не удалось распознать».
    if (ext == 'pdf') {
      return const KaspiParseResult(
        rows: [],
        format: 'pdf',
        warnings: [
          'PDF пока не поддерживается — нужна выписка в Excel или CSV.\n'
              '• Kaspi Business: Личный кабинет → Счета → Выписка → Excel\n'
              '• Kaspi Gold: приложение → Мой банк → Выписка → отправить на почту (xlsx)\n'
              '• Halyk / Forte / Jusan / БЦК: интернет-банк → Счета → Выписка → XLS/CSV\n'
              'Если у вашего банка только PDF — напишите нам, добавим разбор.'
        ],
      );
    }

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

  /// Ручное сопоставление колонок — универсальный запасной путь для банка,
  /// формат которого не распознался автоматически. Пользователь сам указывает,
  /// где дата, где сумма (или дебет/кредит) и где описание.
  ///
  /// [headerRow] — индекс строки шапки; данные читаются со следующей строки.
  /// Нужен хотя бы [dateCol] и один из [amountCol] / [debitCol] / [creditCol].
  static KaspiParseResult parseWithMapping(
    List<List<String>> matrix, {
    required int dateCol,
    int amountCol = -1,
    int debitCol = -1,
    int creditCol = -1,
    int descCol = -1,
    int cpCol = -1,
    int headerRow = 0,
  }) {
    if (dateCol < 0 || (amountCol < 0 && debitCol < 0 && creditCol < 0)) {
      return KaspiParseResult(
        rows: const [],
        format: 'manual',
        matrix: matrix,
        warnings: const ['Укажите колонку с датой и колонку с суммой'],
      );
    }

    final cols = <String, int>{
      'date': dateCol,
      'amount': amountCol,
      'debit': debitCol,
      'credit': creditCol,
      'description': descCol,
      'counterparty': cpCol,
      'balance': -1,
    };

    final rows = <KaspiRow>[];
    final warnings = <String>[];
    for (int i = headerRow + 1; i < matrix.length; i++) {
      final row = matrix[i].map((e) => e.trim()).toList();
      if (row.every((e) => e.isEmpty)) continue;
      try {
        final parsed = _parseRow(row, cols, 'manual');
        if (parsed != null) rows.add(parsed);
      } catch (_) {
        // строку молча пропускаем — при ручной разметке шум ожидаем
      }
    }

    if (rows.isEmpty) {
      warnings.add('По выбранным колонкам не удалось прочитать ни одной строки. '
          'Проверьте, что указали строку шапки и колонку с датой.');
    } else {
      warnings.add('Колонки размечены вручную — проверьте суммы '
          'и где доход/расход.');
    }

    return KaspiParseResult(
      rows: rows,
      format: 'manual',
      matrix: matrix,
      warnings: warnings,
    );
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

    return KaspiParseResult(
        rows: rows, format: format, warnings: warnings, matrix: allRows);
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
  /// Шапка = есть колонка даты И (дебет/кредит ИЛИ сумма).
  ///
  /// Дебет и кредит принимаются и по отдельности: часть банков (БЦК, Jusan)
  /// выгружает только «Списание» либо только «Поступление», а вторая колонка
  /// отсутствует. Раньше такой файл не распознавался вовсе.
  static Map<String, dynamic>? _detectFormat(List<String> headerRow) {
    final dateIdx = _findCol(headerRow, _dateWords);
    if (dateIdx < 0) return null;

    final debitIdx = _findCol(headerRow, _debitWords);
    final creditIdx = _findCol(headerRow, _creditWords);
    var amountIdx = _findCol(headerRow, _amountWords);

    // Одна и та же колонка не может быть и суммой, и дебетом/кредитом
    // («Сумма списания» матчится обоими словарями) — приоритет у дебет/кредит.
    if (amountIdx >= 0 && (amountIdx == debitIdx || amountIdx == creditIdx)) {
      amountIdx = -1;
    }

    final hasAnyDc = debitIdx >= 0 || creditIdx >= 0;
    if (!hasAnyDc && amountIdx < 0) return null;

    final descIdx = _findCol(headerRow, _descWords);
    final cpIdx = _findCol(headerRow, _cpWords);
    final balIdx = _findCol(headerRow, _balWords);

    return {
      'format': (debitIdx >= 0 && creditIdx >= 0) ? 'kaspi_business' : 'generic',
      'cols': {
        'date': dateIdx,
        // сумма остаётся запасным вариантом, если дебет/кредит пустые в строке
        'amount': amountIdx,
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

    // Дебет и кредит рассматриваются независимо: колонки может быть только
    // одна (БЦК/Jusan). Если обе пусты — откатываемся на колонку «Сумма»,
    // где знак определяет доход/расход.
    final credit = (creditIdx >= 0 && creditIdx < row.length)
        ? _parseAmount(row[creditIdx])
        : null;
    final debit = (debitIdx >= 0 && debitIdx < row.length)
        ? _parseAmount(row[debitIdx])
        : null;

    if (credit != null && credit.abs() > 0) {
      amount = credit.abs();
      isIncome = true;
    } else if (debit != null && debit.abs() > 0) {
      amount = debit.abs();
      isIncome = false;
    } else if (amountIdx >= 0 && amountIdx < row.length) {
      final parsed = _parseAmount(row[amountIdx]);
      if (parsed == null || parsed == 0) return null;
      amount = parsed.abs();
      isIncome = parsed > 0;
      // Выписка «только расходы» (есть колонка дебета, нет кредита):
      // беззнаковая сумма — это расход, а не доход.
      if (debitIdx >= 0 && creditIdx < 0 && parsed > 0) isIncome = false;
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
      return KaspiParseResult(
          rows: const [],
          format: 'unknown',
          matrix: allRows,
          warnings: const ['Не удалось распознать формат файла']);
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
      return KaspiParseResult(
          rows: const [],
          format: 'unknown',
          matrix: allRows,
          warnings: const ['Не удалось распознать формат файла (не найдены даты)']);
    }

    // Предпочитаем колонку со знаковыми суммами (есть отрицательные).
    int amountCol = argmax(negHits, exclude: dateCol);
    if (amountCol < 0 || negHits[amountCol] < 1) {
      amountCol = argmax(numHits, exclude: dateCol);
    }
    if (amountCol < 0 || numHits[amountCol] < 2) {
      return KaspiParseResult(
          rows: const [],
          format: 'unknown',
          matrix: allRows,
          warnings: const ['Не удалось распознать формат файла (не найдены суммы)']);
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
      matrix: allRows,
      warnings: rows.isEmpty
          ? ['Не удалось распознать формат файла']
          : ['Формат распознан автоматически по содержимому — '
              'проверьте суммы и где доход/расход.'],
    );
  }

  /// Названия месяцев (рус / каз / англ) для дат вида «12 июля 2026».
  /// Ключ — корень без окончания, чтобы ловить «июль» и «июля».
  static const _monthRoots = <String, int>{
    'янв': 1, 'jan': 1, 'қаңтар': 1, 'кантар': 1,
    'фев': 2, 'feb': 2, 'ақпан': 2, 'акпан': 2,
    'мар': 3, 'mar': 3, 'наурыз': 3,
    'апр': 4, 'apr': 4, 'сәуір': 4, 'сауир': 4,
    'мая': 5, 'май': 5, 'may': 5, 'мамыр': 5,
    'июн': 6, 'jun': 6, 'маусым': 6,
    'июл': 7, 'jul': 7, 'шілде': 7, 'шилде': 7,
    'авг': 8, 'aug': 8, 'тамыз': 8,
    'сен': 9, 'sep': 9, 'қыркүйек': 9, 'кыркуйек': 9,
    'окт': 10, 'oct': 10, 'қазан': 10, 'казан': 10,
    'ноя': 11, 'nov': 11, 'қараша': 11, 'караша': 11,
    'дек': 12, 'dec': 12, 'желтоқсан': 12, 'желтоксан': 12,
  };

  /// Дата вида «12 июля 2026» / «12 шілде 2026» / «12 Jul 2026».
  static DateTime? _parseTextualDate(String t) {
    final m = RegExp(r'^(\d{1,2})\s+([^\s\d]+)\.?\s+(\d{4})$').firstMatch(t);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final year = int.tryParse(m.group(3)!);
    final monthWord = m.group(2)!.toLowerCase();
    if (day == null || year == null) return null;
    for (final e in _monthRoots.entries) {
      if (monthWord.startsWith(e.key)) {
        if (day < 1 || day > 31) return null;
        try {
          final d = DateTime(year, e.value, day);
          // отсекаем «31 февраля» — DateTime молча перекидывает на март
          if (d.month != e.value || d.day != day) return null;
          return d;
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  static DateTime? _parseDate(String s) {
    final patterns = [
      DateFormat('dd.MM.yyyy HH:mm:ss'),
      DateFormat('dd.MM.yyyy HH:mm'),
      DateFormat('dd.MM.yyyy'),
      DateFormat('dd/MM/yyyy HH:mm:ss'),
      DateFormat('dd/MM/yyyy HH:mm'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('dd-MM-yyyy HH:mm'),
      DateFormat('dd-MM-yyyy'),
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('yyyy-MM-dd HH:mm'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('yyyy/MM/dd'),
      DateFormat('yyyy.MM.dd'),
      // двузначный год — Jusan/БЦК так выгружают
      DateFormat('dd.MM.yy'),
      DateFormat('dd/MM/yy'),
      DateFormat('dd-MM-yy'),
    ];

    var t = s.trim();
    if (t.isEmpty) return null;

    // ISO с «T»: 2026-07-28T14:30:00(.123)(Z|+05:00) → берём дату/время
    if (t.contains('T') && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(t)) {
      final iso = DateTime.tryParse(t);
      if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    }

    // «12 июля 2026»
    final textual = _parseTextualDate(t);
    if (textual != null) return textual;

    // хвост вида «14:30» уже покрыт шаблонами; убираем двойные пробелы
    t = t.replaceAll(RegExp(r'\s+'), ' ');

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
        // разделители разрядов: обычный/неразрывный/узкий/тонкий пробел, апостроф
        .replaceAll(RegExp(r"[\s\u00A0\u202F\u2009']"), '')
        .replaceAll('₸', '')
        .replaceAll(RegExp('kzt', caseSensitive: false), '')
        .replaceAll(RegExp('тенге', caseSensitive: false), '')
        .replaceAll(RegExp('тңг', caseSensitive: false), '')
        .replaceAll(RegExp('тг', caseSensitive: false), '')
        // юникод-минусы из PDF/Excel: U+2212, en/em-dash
        .replaceAll(RegExp(r'[\u2212\u2013\u2014]'), '-')
        .trim();

    if (cleaned.isEmpty) return null;

    // Скобки = отрицательное: (1500) -> -1500
    if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      cleaned = '-${cleaned.substring(1, cleaned.length - 1)}';
    }

    // Знак в конце: «1500-» / «1500+» (встречается в банковских выгрузках)
    if (cleaned.endsWith('-')) {
      cleaned = '-${cleaned.substring(0, cleaned.length - 1)}';
    } else if (cleaned.endsWith('+')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);

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
