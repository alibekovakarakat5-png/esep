import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'file_saver.dart';

import '../models/transaction.dart';
import '../models/invoice.dart';
import '../models/client.dart';
import '../models/accounting_client.dart';
import '../constants/kz_tax_constants.dart';

class ExcelExportService {
  ExcelExportService._();

  static final _dateFmt = DateFormat('dd.MM.yyyy');

  // ── Transactions ──────────────────────────────────────────────────────────

  static Future<void> exportTransactions(List<Transaction> transactions) async {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Транзакции');
    final sheet = excel['Транзакции'];

    // Header style
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0099CC'),
      fontColorHex: ExcelColor.white,
    );

    final headers = ['Дата', 'Тип', 'Название', 'Сумма (₸)', 'Клиент', 'Источник', 'Категория', 'Примечание'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // Data
    for (var r = 0; r < transactions.length; r++) {
      final tx = transactions[r];
      final row = r + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(_dateFmt.format(tx.date));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(tx.isIncome ? 'Доход' : 'Расход');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(tx.title);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = DoubleCellValue(tx.amount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(tx.clientName ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(tx.source ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = TextCellValue(tx.category ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = TextCellValue(tx.note ?? '');
    }

    // Totals row
    final totalRow = transactions.length + 1;
    final incomeTotal = transactions.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final expenseTotal = transactions.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);

    final boldStyle = CellStyle(bold: true);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 1)).value = TextCellValue('Итого доходов:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 1)).cellStyle = boldStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 1)).value = DoubleCellValue(incomeTotal);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 1)).cellStyle = boldStyle;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 2)).value = TextCellValue('Итого расходов:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 2)).cellStyle = boldStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 2)).value = DoubleCellValue(expenseTotal);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 2)).cellStyle = boldStyle;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 3)).value = TextCellValue('Прибыль:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 3)).cellStyle = boldStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 3)).value = DoubleCellValue(incomeTotal - expenseTotal);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 3)).cellStyle = boldStyle;

    // Column widths
    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 10);
    sheet.setColumnWidth(2, 30);
    sheet.setColumnWidth(3, 18);
    sheet.setColumnWidth(4, 20);
    sheet.setColumnWidth(5, 14);
    sheet.setColumnWidth(6, 16);
    sheet.setColumnWidth(7, 25);

    await _saveAndShare(excel, 'Esep_Транзакции_${_fileDate()}');
  }

  // ── Invoices ──────────────────────────────────────────────────────────────

  static Future<void> exportInvoices(List<Invoice> invoices) async {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Счета');
    final sheet = excel['Счета'];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0099CC'),
      fontColorHex: ExcelColor.white,
    );

    final headers = ['Номер', 'Дата', 'Клиент', 'Сумма (₸)', 'Статус', 'Срок оплаты', 'Позиции'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    final statusLabels = {
      InvoiceStatus.draft: 'Черновик',
      InvoiceStatus.sent: 'Отправлен',
      InvoiceStatus.paid: 'Оплачен',
      InvoiceStatus.overdue: 'Просрочен',
    };

    for (var r = 0; r < invoices.length; r++) {
      final inv = invoices[r];
      final row = r + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(inv.number);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(_dateFmt.format(inv.createdAt));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(inv.clientName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = DoubleCellValue(inv.totalAmount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(statusLabels[inv.status] ?? inv.status.name);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(inv.dueDate != null ? _dateFmt.format(inv.dueDate!) : '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = TextCellValue(inv.items.map((i) => '${i.description} x${i.quantity}').join('; '));
    }

    final totalRow = invoices.length + 2;
    final boldStyle = CellStyle(bold: true);
    final total = invoices.fold(0.0, (s, i) => s + i.totalAmount);
    final paid = invoices.where((i) => i.status == InvoiceStatus.paid).fold(0.0, (s, i) => s + i.totalAmount);
    final unpaid = total - paid;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow)).value = TextCellValue('Всего:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow)).cellStyle = boldStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow)).value = DoubleCellValue(total);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow)).cellStyle = boldStyle;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 1)).value = TextCellValue('Оплачено:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 1)).value = DoubleCellValue(paid);

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 2)).value = TextCellValue('Не оплачено:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 2)).cellStyle = boldStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 2)).value = DoubleCellValue(unpaid);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow + 2)).cellStyle = boldStyle;

    sheet.setColumnWidth(0, 16);
    sheet.setColumnWidth(1, 14);
    sheet.setColumnWidth(2, 25);
    sheet.setColumnWidth(3, 18);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 14);
    sheet.setColumnWidth(6, 40);

    await _saveAndShare(excel, 'Esep_Счета_${_fileDate()}');
  }

  // ── Clients ───────────────────────────────────────────────────────────────

  static Future<void> exportClients(List<Client> clients) async {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Клиенты');
    final sheet = excel['Клиенты'];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0099CC'),
      fontColorHex: ExcelColor.white,
    );

    final headers = ['Имя', 'БИН/ИИН', 'Телефон', 'Email', 'Адрес', 'Добавлен'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var r = 0; r < clients.length; r++) {
      final c = clients[r];
      final row = r + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(c.name);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(c.bin ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(c.phone ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(c.email ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(c.address ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(_dateFmt.format(c.createdAt));
    }

    sheet.setColumnWidth(0, 25);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 25);
    sheet.setColumnWidth(4, 30);
    sheet.setColumnWidth(5, 14);

    await _saveAndShare(excel, 'Esep_Клиенты_${_fileDate()}');
  }

  // ── Accounting Clients (for accountant mode) ──────────────────────────────

  static Future<void> exportAccountingClients(List<AccountingClient> clients) async {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Клиенты бухгалтера');
    final sheet = excel['Клиенты бухгалтера'];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0099CC'),
      fontColorHex: ExcelColor.white,
    );

    final headers = ['Имя', 'БИН/ИИН', 'Тип', 'Режим', 'Сотрудников', 'Ежемес. плата (₸)', 'Оплата получена', 'Документы', 'Заметки'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var r = 0; r < clients.length; r++) {
      final c = clients[r];
      final row = r + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(c.name);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(c.binOrIin);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(c.entityType.label);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(c.regime.label);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = IntCellValue(c.employees.length);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = DoubleCellValue(c.monthlyFee);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = TextCellValue(c.feeReceivedThisMonth ? 'Да' : 'Нет');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = TextCellValue(c.allDocsReceived ? 'Все получены' : 'Не хватает: ${c.missingDocs}');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = TextCellValue(c.notes ?? '');
    }

    // Totals
    final totalRow = clients.length + 2;
    final boldStyle = CellStyle(bold: true);
    final totalFee = clients.fold(0.0, (s, c) => s + c.monthlyFee);
    final receivedFee = clients.where((c) => c.feeReceivedThisMonth).fold(0.0, (s, c) => s + c.monthlyFee);

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow)).value = TextCellValue('Итого ежемес. плата:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow)).cellStyle = boldStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow)).value = DoubleCellValue(totalFee);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow)).cellStyle = boldStyle;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 1)).value = TextCellValue('Получено:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow + 1)).value = DoubleCellValue(receivedFee);

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 2)).value = TextCellValue('Задолженность:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow + 2)).cellStyle = boldStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow + 2)).value = DoubleCellValue(totalFee - receivedFee);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow + 2)).cellStyle = boldStyle;

    sheet.setColumnWidth(0, 25);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 8);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 20);
    sheet.setColumnWidth(6, 16);
    sheet.setColumnWidth(7, 20);
    sheet.setColumnWidth(8, 30);

    await _saveAndShare(excel, 'Esep_Бухгалтер_Клиенты_${_fileDate()}');
  }

  // ── Full Financial Report (multi-sheet) ───────────────────────────────────

  static Future<void> exportFullReport({
    required List<Transaction> transactions,
    required List<Invoice> invoices,
    required List<Client> clients,
    String? companyName,
    String? companyIin,
  }) async {
    final excel = Excel.createExcel();

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0099CC'),
      fontColorHex: ExcelColor.white,
    );
    final boldStyle = CellStyle(bold: true);

    // ── Sheet 1: Summary ──
    excel.rename('Sheet1', 'Сводка');
    final summary = excel['Сводка'];

    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Финансовый отчёт Esep');
    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = CellStyle(bold: true, fontSize: 14);

    if (companyName != null && companyName.isNotEmpty) {
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Компания: $companyName');
    }
    if (companyIin != null && companyIin.isNotEmpty) {
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('ИИН/БИН: $companyIin');
    }
    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = TextCellValue('Дата: ${_dateFmt.format(DateTime.now())}');

    final incomeTotal = transactions.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final expenseTotal = transactions.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final profit = incomeTotal - expenseTotal;

    var row = 5;
    for (final item in [
      ['Доходы', incomeTotal],
      ['Расходы', expenseTotal],
      ['Прибыль', profit],
    ]) {
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(item[0] as String);
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = boldStyle;
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(item[1] as double);
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = boldStyle;
      row++;
    }

    // Tax estimates
    row += 1;
    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Налоговая оценка (910):');
    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = CellStyle(bold: true, fontSize: 12);
    row++;

    final tax910 = KzTax.calculate910(incomeTotal);
    for (final item in [
      ['ИПН (4%)', tax910.ipn],
      ['Итого 910 налог (4%)', tax910.totalTax],
    ]) {
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(item[0] as String);
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(item[1] as double);
      row++;
    }

    row++;
    final social = KzTax.calculateMonthlySocial();
    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('Ежемесячные соцплатежи:');
    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = CellStyle(bold: true, fontSize: 12);
    row++;
    for (final item in [
      ['ОПВ (10% от МЗП)', social.opv],
      ['ОПВР (3.5% от МЗП)', social.opvr],
      ['СО (5% от МЗП)', social.so],
      ['ВОСМС (5% от 1.4 МЗП)', social.vosms],
      ['Итого в месяц', social.total],
    ]) {
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(item[0] as String);
      summary.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(item[1] as double);
      if ((item[0] as String).startsWith('Итого')) {
        summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = boldStyle;
        summary.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = boldStyle;
      }
      row++;
    }

    summary.setColumnWidth(0, 30);
    summary.setColumnWidth(1, 20);

    // ── Sheet 2: Transactions ──
    final txSheet = excel['Транзакции'];
    final txHeaders = ['Дата', 'Тип', 'Название', 'Сумма (₸)', 'Клиент', 'Источник', 'Категория'];
    for (var i = 0; i < txHeaders.length; i++) {
      final cell = txSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(txHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    for (var r = 0; r < transactions.length; r++) {
      final tx = transactions[r];
      txSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_dateFmt.format(tx.date));
      txSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(tx.isIncome ? 'Доход' : 'Расход');
      txSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(tx.title);
      txSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = DoubleCellValue(tx.amount);
      txSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(tx.clientName ?? '');
      txSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(tx.source ?? '');
      txSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(tx.category ?? '');
    }

    // ── Sheet 3: Invoices ──
    final invSheet = excel['Счета'];
    final invHeaders = ['Номер', 'Дата', 'Клиент', 'Сумма (₸)', 'Статус'];
    for (var i = 0; i < invHeaders.length; i++) {
      final cell = invSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(invHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    final statusLabels = {'draft': 'Черновик', 'sent': 'Отправлен', 'paid': 'Оплачен', 'overdue': 'Просрочен'};
    for (var r = 0; r < invoices.length; r++) {
      final inv = invoices[r];
      invSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(inv.number);
      invSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(_dateFmt.format(inv.createdAt));
      invSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(inv.clientName);
      invSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = DoubleCellValue(inv.totalAmount);
      invSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(statusLabels[inv.status.name] ?? inv.status.name);
    }

    // ── Sheet 4: Clients ──
    final clSheet = excel['Клиенты'];
    final clHeaders = ['Имя', 'БИН/ИИН', 'Телефон', 'Email'];
    for (var i = 0; i < clHeaders.length; i++) {
      final cell = clSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(clHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    for (var r = 0; r < clients.length; r++) {
      final c = clients[r];
      clSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(c.name);
      clSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(c.bin ?? '');
      clSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(c.phone ?? '');
      clSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(c.email ?? '');
    }

    await _saveAndShare(excel, 'Esep_Полный_Отчёт_${_fileDate()}');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _fileDate() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  static Future<void> _saveAndShare(Excel excel, String fileName) async {
    final bytes = excel.encode();
    if (bytes == null) return;

    await saveAndShareFile(bytes, '$fileName.xlsx', subject: fileName);
  }
}
