import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/kz_tax_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/invoice.dart';
import '../../../core/providers/invoice_provider.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/services/pdf_service.dart';
import 'invoices_screen.dart'; // for InvoiceStatusExt
import 'esf_preview_screen.dart';

/// Цвет бренда WhatsApp (как на экране «Кто мне должен»).
const _waGreen = Color(0xFF25D366);

String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// PDF счёта с реквизитами компании из настроек.
Future<pw.Document> _invoicePdf(Invoice invoice, CompanyInfo c) =>
    PdfService.generateInvoice(
      invoice,
      companyName: _nn(c.name),
      companyBin: _nn(c.iin),
      companyAddress: _nn(c.address),
      companyPhone: _nn(c.phone),
      companyBank: _nn(c.bankName),
      companyIik: _nn(c.iik),
      isVatPayer: c.isVatPayer,
    );

Future<pw.Document> _waybillPdf(Invoice invoice, CompanyInfo c) =>
    PdfService.generateWaybillZ2(
      invoice,
      companyName: _nn(c.name),
      companyBin: _nn(c.iin),
      companyAddress: _nn(c.address),
      isVatPayer: c.isVatPayer,
    );

Future<pw.Document> _actPdf(Invoice invoice, CompanyInfo c) =>
    PdfService.generateActR1(
      invoice,
      companyName: _nn(c.name),
      companyBin: _nn(c.iin),
      isVatPayer: c.isVatPayer,
    );

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoiceProvider);
    final invoice = invoices.where((i) => i.id == invoiceId).firstOrNull;
    final company = ref.watch(companyProvider);
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final dateFmt = DateFormat('dd.MM.yyyy');

    if (invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Счёт')),
        body: const Center(child: Text('Счёт не найден')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(invoice.number),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.copy),
            tooltip: 'Дублировать счёт',
            onPressed: () => _duplicate(context, ref, invoice),
          ),
          IconButton(
            icon: const Icon(Iconsax.printer),
            tooltip: 'Печать / PDF',
            onPressed: () => _printPdf(context, invoice, company),
          ),
          IconButton(
            icon: const Icon(Iconsax.share),
            tooltip: 'Поделиться',
            onPressed: () => _sharePdf(context, invoice, company),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Документы: накладная, акт',
            onPressed: () => _docsMenu(context, invoice, company),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status + amount header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: invoice.status.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: invoice.status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  invoice.status.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: invoice.status.color,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${fmt.format(invoice.totalAmount)} ₸',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: invoice.status.color,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Номер', value: invoice.number),
                  _InfoRow(label: 'Клиент', value: invoice.clientName),
                  _InfoRow(label: 'Дата создания', value: dateFmt.format(invoice.createdAt)),
                  if (invoice.dueDate != null)
                    _InfoRow(label: 'Оплатить до', value: dateFmt.format(invoice.dueDate!)),
                  if (invoice.paymentLink != null && invoice.paymentLink!.isNotEmpty)
                    _InfoRow(label: 'Оплата онлайн', value: invoice.paymentLink!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Items
          const Text('Позиции',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: EsepColors.textPrimary)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Header row
                  const Row(children: [
                    Expanded(flex: 4, child: Text('Наименование', style: TextStyle(fontSize: 11, color: EsepColors.textSecondary, fontWeight: FontWeight.w600))),
                    Expanded(flex: 1, child: Text('Кол.', style: TextStyle(fontSize: 11, color: EsepColors.textSecondary, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text('Цена', style: TextStyle(fontSize: 11, color: EsepColors.textSecondary, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                    Expanded(flex: 2, child: Text('Сумма', style: TextStyle(fontSize: 11, color: EsepColors.textSecondary, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                  ]),
                  const Divider(height: 16),
                  ...invoice.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(flex: 4, child: Text(item.description, style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 1, child: Text(_fmtQty(item.quantity), style: const TextStyle(fontSize: 13), textAlign: TextAlign.center)),
                      Expanded(flex: 2, child: Text('${fmt.format(item.unitPrice)} ₸', style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text('${fmt.format(item.total)} ₸', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                    ]),
                  )),
                  const Divider(height: 16),
                  Row(children: [
                    const Expanded(child: Text('Итого', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                    Text('${fmt.format(invoice.totalAmount)} ₸',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: EsepColors.primary)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Note
          if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Примечание', style: TextStyle(fontSize: 13, color: EsepColors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(invoice.notes!, style: const TextStyle(fontSize: 14)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action buttons
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showStatusMenu(context, ref, invoice),
                icon: const Icon(Iconsax.edit_2, size: 18),
                label: const Text('Статус'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EsfPreviewScreen(invoice: invoice)),
                ),
                icon: const Icon(Iconsax.document_code, size: 18),
                label: const Text('ЭСФ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _previewPdf(context, invoice, company),
                icon: const Icon(Iconsax.document, size: 18),
                label: const Text('PDF'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _sendWhatsApp(context, invoice, company),
              icon: const Icon(Iconsax.message, size: 18, color: _waGreen),
              label: const Text('Отправить клиенту в WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w600, color: _waGreen)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _waGreen),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _previewPdf(BuildContext context, Invoice invoice, CompanyInfo company) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PdfPreviewPage(invoice: invoice, company: company),
      ),
    );
  }

  Future<void> _printPdf(BuildContext context, Invoice invoice, CompanyInfo company) async {
    final pdf = await _invoicePdf(invoice, company);
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  Future<void> _sharePdf(BuildContext context, Invoice invoice, CompanyInfo company) async {
    final pdf = await _invoicePdf(invoice, company);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${invoice.number}.pdf',
    );
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref, Invoice invoice) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final number =
          await ref.read(invoiceProvider.notifier).duplicate(invoice);
      messenger.showSnackBar(
          SnackBar(content: Text('Создана копия: $number (черновик)')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: $e')));
    }
  }

  /// Открывает WhatsApp с готовым текстом счёта (сумма с НДС, если платит НДС,
  /// плюс ссылка на онлайн-оплату, если указана). Чат выбирает пользователь.
  Future<void> _sendWhatsApp(
      BuildContext context, Invoice invoice, CompanyInfo company) async {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final net = invoice.totalAmount;
    final gross = company.isVatPayer ? net * (1 + KzTax.vatRate) : net;
    final b = StringBuffer()
      ..writeln('Здравствуйте! Счёт ${invoice.number} '
          'от ${DateFormat('dd.MM.yyyy').format(invoice.createdAt)} '
          'на сумму ${fmt.format(gross)} ₸.');
    if (invoice.dueDate != null) {
      b.writeln(
          'Оплатить до ${DateFormat('dd.MM.yyyy').format(invoice.dueDate!)}.');
    }
    if (invoice.paymentLink != null && invoice.paymentLink!.isNotEmpty) {
      b.writeln('Оплата онлайн: ${invoice.paymentLink}');
    }
    if (company.name.trim().isNotEmpty) b.write('— ${company.name.trim()}');
    final uri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(b.toString())}');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Не удалось открыть WhatsApp')));
      }
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось открыть WhatsApp')));
    }
  }

  // Меню первичных документов из одного счёта: счёт / накладная З-2 / акт Р-1.
  void _docsMenu(BuildContext context, Invoice invoice, CompanyInfo company) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Сформировать документ', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: EsepColors.primary),
            title: const Text('Счёт на оплату'),
            onTap: () async {
              Navigator.pop(ctx);
              final pdf = await _invoicePdf(invoice, company);
              await Printing.sharePdf(bytes: await pdf.save(), filename: 'Счёт-${invoice.number}.pdf');
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined, color: EsepColors.primary),
            title: const Text('Накладная (форма З-2)'),
            subtitle: const Text('на отпуск запасов на сторону'),
            onTap: () async {
              Navigator.pop(ctx);
              final pdf = await _waybillPdf(invoice, company);
              await Printing.sharePdf(bytes: await pdf.save(), filename: 'Накладная-${invoice.number}.pdf');
            },
          ),
          ListTile(
            leading: const Icon(Icons.assignment_turned_in_outlined, color: EsepColors.primary),
            title: const Text('Акт выполненных работ (Р-1)'),
            subtitle: const Text('оказанных услуг'),
            onTap: () async {
              Navigator.pop(ctx);
              final pdf = await _actPdf(invoice, company);
              await Printing.sharePdf(bytes: await pdf.save(), filename: 'Акт-${invoice.number}.pdf');
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showStatusMenu(BuildContext context, WidgetRef ref, Invoice invoice) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Изменить статус', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ...InvoiceStatus.values.map((s) => ListTile(
            leading: Icon(Icons.circle, color: s.color, size: 12),
            title: Text(s.label),
            trailing: invoice.status == s ? const Icon(Icons.check, color: EsepColors.primary) : null,
            onTap: () {
              ref.read(invoiceProvider.notifier).updateStatus(invoice.id, s);
              Navigator.pop(ctx);
            },
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(
        width: 120,
        child: Text(label, style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
      ),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );
}

class _PdfPreviewPage extends StatelessWidget {
  const _PdfPreviewPage({required this.invoice, required this.company});
  final Invoice invoice;
  final CompanyInfo company;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('PDF ${invoice.number}'),
      actions: [
        IconButton(
          icon: const Icon(Iconsax.share),
          onPressed: () async {
            final pdf = await _invoicePdf(invoice, company);
            await Printing.sharePdf(
              bytes: await pdf.save(),
              filename: '${invoice.number}.pdf',
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: PdfPreview(
      build: (_) async {
        final pdf = await _invoicePdf(invoice, company);
        return pdf.save();
      },
      canChangeOrientation: false,
      canChangePageFormat: false,
      pdfFileName: '${invoice.number}.pdf',
    ),
  );
}

String _fmtQty(double q) =>
    q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
