import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../models/invoice.dart';
import '../models/transaction.dart';
import '../constants/kz_tax_constants.dart';

class PdfService {
  PdfService._();

  static const _blue = PdfColor.fromInt(0xFF0099CC);
  static const _dark = PdfColor.fromInt(0xFF1A1D23);
  static const _grey = PdfColor.fromInt(0xFF6B7280);
  static const _lightBg = PdfColor.fromInt(0xFFF8F9FA);
  static const _divider = PdfColor.fromInt(0xFFE8ECEF);

  static final _fmt = NumberFormat('#,##0', 'ru_RU');
  static final _dateFmt = DateFormat('dd.MM.yyyy');

  static Future<pw.Document> generateInvoice(
    Invoice invoice, {
    String? companyName,
    String? companyBin,
    String? companyAddress,
    String? companyPhone,
    String? companyBank,
    String? companyIik,
  }) async {
    final pdf = pw.Document(
      title: 'Счёт ${invoice.number}',
      author: companyName ?? 'Есеп',
    );

    final company = companyName ?? 'ИП «Моя компания»';
    final bin = companyBin ?? '';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(invoice, company, bin),
            pw.SizedBox(height: 24),

            // Seller / Buyer info
            _buildParties(
              invoice,
              company: company,
              bin: bin,
              address: companyAddress,
              phone: companyPhone,
              bank: companyBank,
              iik: companyIik,
            ),
            pw.SizedBox(height: 24),

            // Items table
            _buildItemsTable(invoice),
            pw.SizedBox(height: 16),

            // Totals
            _buildTotals(invoice),
            pw.SizedBox(height: 24),

            // Note
            if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
              pw.Text('Примечание:',
                  style: pw.TextStyle(
                      fontSize: 10,
                      color: _grey,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(invoice.notes!,
                  style: const pw.TextStyle(fontSize: 10, color: _dark)),
              pw.SizedBox(height: 24),
            ],

            pw.Spacer(),

            // Signature line
            _buildSignature(company),
          ],
        ),
      ),
    );

    return pdf;
  }

  static pw.Widget _buildHeader(
      Invoice invoice, String company, String bin) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(company,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: _blue)),
              if (bin.isNotEmpty)
                pw.Text('БИН/ИИН: $bin',
                    style: const pw.TextStyle(fontSize: 9, color: _grey)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: pw.BoxDecoration(
                color: _blue,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(
                'СЧЁТ НА ОПЛАТУ',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(invoice.number,
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _dark)),
            pw.SizedBox(height: 2),
            pw.Text('от ${_dateFmt.format(invoice.createdAt)}',
                style: const pw.TextStyle(fontSize: 10, color: _grey)),
            if (invoice.dueDate != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                  'Оплатить до: ${_dateFmt.format(invoice.dueDate!)}',
                  style: pw.TextStyle(
                      fontSize: 10,
                      color: const PdfColor.fromInt(0xFFE74C3C),
                      fontWeight: pw.FontWeight.bold)),
            ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildParties(
    Invoice invoice, {
    required String company,
    required String bin,
    String? address,
    String? phone,
    String? bank,
    String? iik,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _lightBg,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: _divider),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Поставщик',
                    style: pw.TextStyle(
                        fontSize: 8,
                        color: _grey,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(company,
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _dark)),
                if (bin.isNotEmpty)
                  _infoLine('БИН/ИИН', bin),
                if (address != null && address.isNotEmpty)
                  _infoLine('Адрес', address),
                if (phone != null && phone.isNotEmpty)
                  _infoLine('Тел', phone),
                if (bank != null && bank.isNotEmpty)
                  _infoLine('Банк', bank),
                if (iik != null && iik.isNotEmpty)
                  _infoLine('ИИК', iik),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _lightBg,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: _divider),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Покупатель',
                    style: pw.TextStyle(
                        fontSize: 8,
                        color: _grey,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(invoice.clientName,
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _dark)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _infoLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.Row(children: [
        pw.Text('$label: ',
            style: const pw.TextStyle(fontSize: 9, color: _grey)),
        pw.Expanded(
            child: pw.Text(value,
                style: const pw.TextStyle(fontSize: 9, color: _dark))),
      ]),
    );
  }

  static pw.Widget _buildItemsTable(Invoice invoice) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: _divider),
      headerStyle: pw.TextStyle(
          fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _blue),
      headerAlignment: pw.Alignment.centerLeft,
      cellStyle: const pw.TextStyle(fontSize: 10, color: _dark),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FlexColumnWidth(1.5),
      },
      headers: ['#', 'Наименование', 'Кол-во', 'Цена', 'Сумма'],
      data: List.generate(
        invoice.items.length,
        (i) {
          final item = invoice.items[i];
          return [
            '${i + 1}',
            item.description,
            item.quantity == item.quantity.truncateToDouble()
                ? item.quantity.toInt().toString()
                : item.quantity.toString(),
            '${_fmt.format(item.unitPrice)} ₸',
            '${_fmt.format(item.total)} ₸',
          ];
        },
      ),
      cellAlignments: {
        0: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      oddRowDecoration: const pw.BoxDecoration(color: _lightBg),
    );
  }

  static pw.Widget _buildTotals(Invoice invoice) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: _lightBg,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _divider),
        ),
        child: pw.Column(children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Без НДС:',
                  style: const pw.TextStyle(fontSize: 10, color: _grey)),
              pw.Text('${_fmt.format(invoice.totalAmount)} ₸',
                  style: const pw.TextStyle(fontSize: 10, color: _dark)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('НДС (12%):',
                  style: const pw.TextStyle(fontSize: 10, color: _grey)),
              pw.Text('не облагается',
                  style: const pw.TextStyle(fontSize: 10, color: _grey)),
            ],
          ),
          pw.Divider(color: _divider, height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Итого к оплате:',
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _dark)),
              pw.Text('${_fmt.format(invoice.totalAmount)} ₸',
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _blue)),
            ],
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ФИНАНСОВЫЙ ОТЧЁТ ДЛЯ БУХГАЛТЕРА
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<pw.Document> generateReport({
    required List<Transaction> transactions,
    required String period,
    String? companyName,
    String? companyBin,
  }) async {
    final pdf = pw.Document(
      title: 'Финансовый отчёт — $period',
      author: companyName ?? 'Есеп',
    );

    final company = companyName ?? 'ИП';
    final bin = companyBin ?? '';

    final incomes = transactions.where((t) => t.isIncome).toList();
    final expenses = transactions.where((t) => !t.isIncome).toList();
    final totalIncome = incomes.fold(0.0, (s, t) => s + t.amount);
    final totalExpense = expenses.fold(0.0, (s, t) => s + t.amount);
    final profit = totalIncome - totalExpense;

    // Tax calculation
    final tax910 = KzTax.calculate910(totalIncome);
    final social = KzTax.calculateMonthlySocial();
    // Determine months count from transactions
    final months = _uniqueMonths(transactions);
    final socialTotal = social.total * months;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (ctx) => _reportHeader(company, bin, period, ctx),
      footer: (ctx) => _reportFooter(ctx),
      build: (ctx) => [
        // Summary cards
        pw.SizedBox(height: 16),
        _reportSummaryRow(totalIncome, totalExpense, profit),
        pw.SizedBox(height: 20),

        // Tax summary
        _reportTaxSection(tax910, social, socialTotal, months),
        pw.SizedBox(height: 20),

        // Income table
        if (incomes.isNotEmpty) ...[
          _reportSectionTitle('Доходы', totalIncome),
          pw.SizedBox(height: 8),
          _reportTransactionTable(incomes),
          pw.SizedBox(height: 20),
        ],

        // Expense table
        if (expenses.isNotEmpty) ...[
          _reportSectionTitle('Расходы', totalExpense),
          pw.SizedBox(height: 8),
          _reportTransactionTable(expenses),
          pw.SizedBox(height: 20),
        ],

        // Category breakdown
        _reportCategoryBreakdown(transactions),
      ],
    ));

    return pdf;
  }

  static int _uniqueMonths(List<Transaction> txs) {
    if (txs.isEmpty) return 1;
    final months = <String>{};
    for (final t in txs) {
      months.add('${t.date.year}-${t.date.month}');
    }
    return months.length.clamp(1, 12);
  }

  static pw.Widget _reportHeader(String company, String bin, String period, pw.Context ctx) {
    return pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(company, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _blue)),
            if (bin.isNotEmpty)
              pw.Text('БИН/ИИН: $bin', style: const pw.TextStyle(fontSize: 9, color: _grey)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: pw.BoxDecoration(color: _blue, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text('ФИНАНСОВЫЙ ОТЧЁТ',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ),
            pw.SizedBox(height: 4),
            pw.Text(period, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _dark)),
          ]),
        ],
      ),
      pw.Divider(color: _divider, height: 16),
    ]);
  }

  static pw.Widget _reportFooter(pw.Context ctx) {
    return pw.Column(children: [
      pw.Divider(color: _divider),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Сформировано в Есеп · ${_dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: _grey)),
        pw.Text('Стр. ${ctx.pageNumber} из ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _grey)),
      ]),
    ]);
  }

  static pw.Widget _reportSummaryRow(double income, double expense, double profit) {
    return pw.Row(children: [
      _reportMetricBox('Доход', income, const PdfColor.fromInt(0xFF27AE60)),
      pw.SizedBox(width: 12),
      _reportMetricBox('Расход', expense, const PdfColor.fromInt(0xFFE74C3C)),
      pw.SizedBox(width: 12),
      _reportMetricBox('Прибыль', profit, profit >= 0 ? _blue : const PdfColor.fromInt(0xFFE74C3C)),
    ]);
  }

  static pw.Widget _reportMetricBox(String label, double amount, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _divider),
          color: _lightBg,
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _grey)),
          pw.SizedBox(height: 4),
          pw.Text('${_fmt.format(amount)} ₸',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  static pw.Widget _reportTaxSection(TaxCalculation910 tax, SocialPayments social, double socialTotal, int months) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _divider),
        color: _lightBg,
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Налоги и соцплатежи (910 упрощёнка)',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _dark)),
        pw.SizedBox(height: 8),
        _taxRow('ИПН (1.5%)', tax.ipn),
        _taxRow('СН (1.5%)', tax.sn),
        _taxRow('Итого налог (3%)', tax.totalTax, bold: true),
        pw.Divider(color: _divider, height: 12),
        _taxRow('ОПВ (10% от МЗП × $months мес)', social.opv * months),
        _taxRow('ОПВР (3.5% от МЗП × $months мес)', social.opvr * months),
        _taxRow('СО (5% от МЗП × $months мес)', social.so * months),
        _taxRow('ВОСМС (5% от 1.4 МЗП × $months мес)', social.vosms * months),
        _taxRow('Итого соцплатежи', socialTotal, bold: true),
        pw.Divider(color: _divider, height: 12),
        _taxRow('ВСЕГО К УПЛАТЕ', tax.totalTax + socialTotal, bold: true, color: _blue),
      ]),
    );
  }

  static pw.Widget _taxRow(String label, double amount, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: pw.TextStyle(
          fontSize: 9,
          color: color ?? (bold ? _dark : _grey),
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        )),
        pw.Text('${_fmt.format(amount)} ₸', style: pw.TextStyle(
          fontSize: 9,
          color: color ?? (bold ? _dark : _grey),
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        )),
      ]),
    );
  }

  static pw.Widget _reportSectionTitle(String title, double total) {
    return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _dark)),
      pw.Text('${_fmt.format(total)} ₸', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _dark)),
    ]);
  }

  static pw.Widget _reportTransactionTable(List<Transaction> txs) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: _divider),
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _blue),
      cellStyle: const pw.TextStyle(fontSize: 9, color: _dark),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),
        1: const pw.FixedColumnWidth(65),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(1.5),
      },
      headers: ['#', 'Дата', 'Описание', 'Контрагент', 'Сумма'],
      data: List.generate(txs.length, (i) {
        final t = txs[i];
        return [
          '${i + 1}',
          _dateFmt.format(t.date),
          t.title,
          t.clientName ?? '',
          '${_fmt.format(t.amount)} ₸',
        ];
      }),
      cellAlignments: {0: pw.Alignment.center, 4: pw.Alignment.centerRight},
      headerAlignments: {0: pw.Alignment.center, 4: pw.Alignment.centerRight},
      oddRowDecoration: const pw.BoxDecoration(color: _lightBg),
    );
  }

  static pw.Widget _reportCategoryBreakdown(List<Transaction> txs) {
    final expenses = txs.where((t) => !t.isIncome).toList();
    if (expenses.isEmpty) return pw.SizedBox();

    // Group by category
    final byCategory = <String, double>{};
    for (final t in expenses) {
      final cat = t.category ?? 'Прочее';
      byCategory[cat] = (byCategory[cat] ?? 0) + t.amount;
    }
    final sorted = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold(0.0, (s, e) => s + e.value);

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Расходы по категориям', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _dark)),
      pw.SizedBox(height: 8),
      ...sorted.map((e) {
        final pct = total > 0 ? (e.value / total * 100).toStringAsFixed(1) : '0';
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(children: [
            pw.SizedBox(width: 120, child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 9, color: _dark))),
            pw.Expanded(child: pw.ClipRRect(
              horizontalRadius: 3,
              verticalRadius: 3,
              child: pw.Container(
                height: 10,
                decoration: pw.BoxDecoration(color: _lightBg, borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Container(
                    width: 200 * (total > 0 ? e.value / total : 0),
                    height: 10,
                    decoration: pw.BoxDecoration(color: _blue, borderRadius: pw.BorderRadius.circular(3)),
                  ),
                ),
              ),
            )),
            pw.SizedBox(width: 8),
            pw.SizedBox(width: 80, child: pw.Text(
              '${_fmt.format(e.value)} ₸ ($pct%)',
              style: const pw.TextStyle(fontSize: 8, color: _grey),
              textAlign: pw.TextAlign.right,
            )),
          ]),
        );
      }),
    ]);
  }

  static pw.Widget _buildSignature(String company) {
    return pw.Row(children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Поставщик',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: _grey,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 24),
            pw.Container(
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _dark))),
              width: 200,
              height: 1,
            ),
            pw.SizedBox(height: 4),
            pw.Text(company,
                style: const pw.TextStyle(fontSize: 9, color: _grey)),
          ],
        ),
      ),
      pw.SizedBox(width: 40),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Покупатель',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: _grey,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 24),
            pw.Container(
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _dark))),
              width: 200,
              height: 1,
            ),
            pw.SizedBox(height: 4),
            pw.Text('подпись / печать',
                style: const pw.TextStyle(fontSize: 9, color: _grey)),
          ],
        ),
      ),
    ]);
  }
}
