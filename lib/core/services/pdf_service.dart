import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../models/invoice.dart';

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
