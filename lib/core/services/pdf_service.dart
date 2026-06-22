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
    bool isVatPayer = false,
  }) async {
    final pdf = pw.Document(
      title: 'Счёт ${invoice.number}',
      author: companyName ?? 'Esep',
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
            _buildTotals(invoice, isVatPayer: isVatPayer),
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

  static pw.Widget _buildTotals(Invoice invoice, {bool isVatPayer = false}) {
    final net = invoice.totalAmount;
    final vatRate = KzTax.vatRate; // 0.16
    final vat = isVatPayer ? net * vatRate : 0.0;
    final gross = net + vat;

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
              pw.Text('${_fmt.format(net)} ₸',
                  style: const pw.TextStyle(fontSize: 10, color: _dark)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('НДС (16%):',
                  style: const pw.TextStyle(fontSize: 10, color: _grey)),
              pw.Text(
                isVatPayer ? '${_fmt.format(vat)} ₸' : 'не облагается',
                style: const pw.TextStyle(fontSize: 10, color: _grey),
              ),
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
              pw.Text('${_fmt.format(gross)} ₸',
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
      author: companyName ?? 'Esep',
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
        pw.Text('Сформировано в Esep · ${_dateFmt.format(DateTime.now())}',
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
    final rateLabel = _percentLabel(KzTax.simplified910TotalRate);
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
        _taxRow('ИПН ($rateLabel)', tax.ipn),
        _taxRow('СН (0%)', tax.sn),
        _taxRow('Итого налог ($rateLabel)', tax.totalTax, bold: true),
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

  static String _percentLabel(double rate) {
    final percent = rate * 100;
    return percent == percent.roundToDouble()
        ? '${percent.toStringAsFixed(0)}%'
        : '${percent.toStringAsFixed(1)}%';
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

  // ═══════════════════════════════════════════════════════════════════════════
  // НАКЛАДНАЯ НА ОТПУСК ЗАПАСОВ НА СТОРОНУ — Форма З-2
  // (Приказ Минфина РК №562, прил.26). Данные берём из счёта (Invoice).
  // ⚠ Точность бланка/граф валидируется бухгалтером-тестировщиком.
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<pw.Document> generateWaybillZ2(
    Invoice invoice, {
    String? companyName,
    String? companyBin,
    String? companyAddress,
    bool isVatPayer = false,
  }) async {
    final pdf = pw.Document(
      title: 'Накладная З-2 ${invoice.number}',
      author: companyName ?? 'Esep',
    );
    final company = companyName ?? 'ИП «Моя компания»';
    final bin = companyBin ?? '';
    final shipper = invoice.consignorSameAsSeller
        ? company
        : (invoice.consignorName ?? company);
    final receiver = invoice.consigneeSameAsCustomer
        ? invoice.clientName
        : (invoice.consigneeName ?? invoice.clientName);
    final net = invoice.totalAmount;
    final vat = isVatPayer ? net * KzTax.vatRate : 0.0;
    final gross = net + vat;

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _docTitle('НАКЛАДНАЯ № ${invoice.number}',
              'на отпуск запасов на сторону (форма З-2)',
              'от ${_dateFmt.format(invoice.createdAt)}'),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            pw.Expanded(child: _docBox('Организация-отправитель', [
              shipper,
              if (bin.isNotEmpty) 'БИН/ИИН: $bin',
              if (companyAddress != null && companyAddress.isNotEmpty)
                companyAddress,
            ])),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _docBox('Организация-получатель', [
              receiver,
              if (invoice.buyerIin != null && invoice.buyerIin!.isNotEmpty)
                'БИН/ИИН: ${invoice.buyerIin}',
            ])),
          ]),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            pw.Expanded(child: _infoLine('Через кого затребовано', '')),
            pw.Expanded(child: _infoLine('Транспортная организация', '')),
            pw.Expanded(child: _infoLine('ТТН (№, дата)',
                invoice.deliveryDocNum ?? '')),
          ]),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: _divider),
            headerStyle: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _blue),
            cellStyle: const pw.TextStyle(fontSize: 8, color: _dark),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            columnWidths: {
              0: const pw.FixedColumnWidth(22),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1.1),
              5: const pw.FlexColumnWidth(1.1),
              6: const pw.FlexColumnWidth(1.4),
              7: const pw.FlexColumnWidth(1.4),
              8: const pw.FlexColumnWidth(1.4),
            },
            headers: const [
              '№', 'Наименование, характеристика', 'Номенкл. №', 'Ед.изм.',
              'Кол-во подлежит', 'Кол-во отпущено', 'Цена, ₸', 'Сумма НДС, ₸',
              'Сумма с НДС, ₸'
            ],
            data: List.generate(invoice.items.length, (i) {
              final it = invoice.items[i];
              final itVat = isVatPayer ? it.total * KzTax.vatRate : 0.0;
              final qty = it.quantity == it.quantity.truncateToDouble()
                  ? it.quantity.toInt().toString()
                  : it.quantity.toString();
              return [
                '${i + 1}', it.description, it.catalogTruId, it.unitName,
                qty, qty, _fmt.format(it.unitPrice),
                isVatPayer ? _fmt.format(itVat) : '—',
                _fmt.format(it.total + itVat),
              ];
            }),
            cellAlignments: {
              0: pw.Alignment.center, 3: pw.Alignment.center,
              4: pw.Alignment.center, 5: pw.Alignment.center,
              6: pw.Alignment.centerRight, 7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: _lightBg),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
              'Всего отпущено ${invoice.items.length} наименований на сумму ${_fmt.format(gross)} ₸',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _dark)),
          pw.Text('Сумма прописью: ${_amountInWords(gross)}',
              style: const pw.TextStyle(fontSize: 9, color: _grey)),
          pw.Spacer(),
          _docSignatures3(),
        ],
      ),
    ));
    return pdf;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // АКТ ВЫПОЛНЕННЫХ РАБОТ (ОКАЗАННЫХ УСЛУГ) — Форма Р-1
  // (Приказ Минфина РК №562, прил.50). Данные из счёта (Invoice).
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<pw.Document> generateActR1(
    Invoice invoice, {
    String? companyName,
    String? companyBin,
    bool isVatPayer = false,
  }) async {
    final pdf = pw.Document(
      title: 'Акт Р-1 ${invoice.number}',
      author: companyName ?? 'Esep',
    );
    final company = companyName ?? 'ИП «Моя компания»';
    final bin = companyBin ?? '';
    final net = invoice.totalAmount;
    final gross = net + (isVatPayer ? net * KzTax.vatRate : 0.0);

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _docTitle('АКТ № ${invoice.number}',
              'выполненных работ (оказанных услуг) — форма Р-1',
              'от ${_dateFmt.format(invoice.createdAt)}'),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            pw.Expanded(child: _docBox('Исполнитель', [
              company,
              if (bin.isNotEmpty) 'БИН/ИИН: $bin',
            ])),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _docBox('Заказчик', [
              invoice.clientName,
              if (invoice.buyerIin != null && invoice.buyerIin!.isNotEmpty)
                'БИН/ИИН: ${invoice.buyerIin}',
            ])),
          ]),
          if (invoice.hasContract) ...[
            pw.SizedBox(height: 6),
            _infoLine('Договор',
                '№ ${invoice.contractNum}'
                '${invoice.contractDate != null ? ' от ${_dateFmt.format(invoice.contractDate!)}' : ''}'),
          ],
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: _divider),
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _blue),
            cellStyle: const pw.TextStyle(fontSize: 9, color: _dark),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            columnWidths: {
              0: const pw.FixedColumnWidth(26),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1.5),
              6: const pw.FlexColumnWidth(1.5),
            },
            headers: const [
              '№', 'Наименование работ (услуг)', 'Дата', 'Ед.изм.',
              'Кол-во', 'Цена, ₸', 'Стоимость, ₸'
            ],
            data: List.generate(invoice.items.length, (i) {
              final it = invoice.items[i];
              final qty = it.quantity == it.quantity.truncateToDouble()
                  ? it.quantity.toInt().toString()
                  : it.quantity.toString();
              return [
                '${i + 1}', it.description, _dateFmt.format(invoice.createdAt),
                it.unitName, qty, _fmt.format(it.unitPrice), _fmt.format(it.total),
              ];
            }),
            cellAlignments: {
              0: pw.Alignment.center, 2: pw.Alignment.center,
              3: pw.Alignment.center, 4: pw.Alignment.center,
              5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: _lightBg),
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Всего к оплате: ${_fmt.format(gross)} ₸'
                '${isVatPayer ? ' (в т.ч. НДС 16%)' : ''}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _blue)),
          ),
          pw.Text('Сумма прописью: ${_amountInWords(gross)}',
              style: const pw.TextStyle(fontSize: 9, color: _grey)),
          pw.SizedBox(height: 6),
          pw.Text(
              'Вышеперечисленные работы (услуги) выполнены полностью и в срок. '
              'Заказчик претензий по объёму, качеству и срокам оказания услуг не имеет.',
              style: const pw.TextStyle(fontSize: 8, color: _grey)),
          pw.Spacer(),
          _docSignatures2('Сдал (Исполнитель)', 'Принял (Заказчик)'),
        ],
      ),
    ));
    return pdf;
  }

  // ── Общие хелперы для первичных документов ─────────────────────────────────
  static pw.Widget _docTitle(String title, String subtitle, String date) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Center(child: pw.Text(title,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _dark))),
      pw.SizedBox(height: 2),
      pw.Center(child: pw.Text(subtitle,
          style: const pw.TextStyle(fontSize: 10, color: _grey))),
      pw.SizedBox(height: 2),
      pw.Center(child: pw.Text(date, style: const pw.TextStyle(fontSize: 9, color: _grey))),
    ]);
  }

  static pw.Widget _docBox(String label, List<String> lines) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _divider),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 8, color: _grey, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        ...lines.map((l) => pw.Text(l, style: const pw.TextStyle(fontSize: 10, color: _dark))),
      ]),
    );
  }

  static pw.Widget _docSignatures2(String left, String right) {
    return pw.Row(children: [
      pw.Expanded(child: _sigBlock(left)),
      pw.SizedBox(width: 40),
      pw.Expanded(child: _sigBlock(right)),
    ]);
  }

  static pw.Widget _docSignatures3() {
    return pw.Row(children: [
      pw.Expanded(child: _sigBlock('Отпустил')),
      pw.SizedBox(width: 20),
      pw.Expanded(child: _sigBlock('Получил')),
      pw.SizedBox(width: 20),
      pw.Expanded(child: _sigBlock('Главный бухгалтер')),
    ]);
  }

  static pw.Widget _sigBlock(String label) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(label,
          style: pw.TextStyle(fontSize: 9, color: _grey, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 20),
      pw.Container(
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _dark))),
          height: 1),
      pw.SizedBox(height: 3),
      pw.Text('подпись / Ф.И.О. / печать',
          style: const pw.TextStyle(fontSize: 8, color: _grey)),
    ]);
  }

  // ── Сумма прописью (тенге) ─────────────────────────────────────────────────
  static const _ones = ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  static const _onesF = ['', 'одна', 'две', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  static const _teens = ['десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать'];
  static const _tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто'];
  static const _hundreds = ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'];

  static String _triad(int n, bool feminine) {
    final h = n ~/ 100, t = (n % 100) ~/ 10, o = n % 10;
    final parts = <String>[];
    if (h > 0) parts.add(_hundreds[h]);
    if (t == 1) {
      parts.add(_teens[o]);
    } else {
      if (t > 1) parts.add(_tens[t]);
      if (o > 0) parts.add(feminine ? _onesF[o] : _ones[o]);
    }
    return parts.join(' ');
  }

  static String _plural(int n, String one, String few, String many) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return one;
    if (n10 >= 2 && n10 <= 4 && (n100 < 10 || n100 >= 20)) return few;
    return many;
  }

  static String _intToWords(int n) {
    if (n == 0) return 'ноль';
    final parts = <String>[];
    var rem = n;
    final scales = [
      [1000000000, 'миллиард', 'миллиарда', 'миллиардов', 0],
      [1000000, 'миллион', 'миллиона', 'миллионов', 0],
      [1000, 'тысяча', 'тысячи', 'тысяч', 1],
    ];
    for (final s in scales) {
      final div = s[0] as int;
      final cnt = rem ~/ div;
      if (cnt > 0) {
        parts.add(_triad(cnt, (s[4] as int) == 1));
        parts.add(_plural(cnt, s[1] as String, s[2] as String, s[3] as String));
        rem %= div;
      }
    }
    if (rem > 0) parts.add(_triad(rem, false));
    return parts.where((p) => p.isNotEmpty).join(' ');
  }

  static String _amountInWords(double amount) {
    final whole = amount.floor();
    final kop = ((amount - whole) * 100).round();
    final w = _intToWords(whole);
    final cap = w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';
    return '$cap тенге ${kop.toString().padLeft(2, '0')} тиын';
  }
}
