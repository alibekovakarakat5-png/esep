import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/invoice.dart';
import '../../../core/providers/invoice_provider.dart';
import '../../../core/services/pdf_service.dart';
import 'invoices_screen.dart'; // for InvoiceStatusExt
import 'esf_preview_screen.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoiceProvider);
    final invoice = invoices.where((i) => i.id == invoiceId).firstOrNull;
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
            icon: const Icon(Iconsax.printer),
            tooltip: 'Печать / PDF',
            onPressed: () => _printPdf(context, invoice),
          ),
          IconButton(
            icon: const Icon(Iconsax.share),
            tooltip: 'Поделиться',
            onPressed: () => _sharePdf(context, invoice),
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
                      Expanded(flex: 1, child: Text('${item.quantity}', style: const TextStyle(fontSize: 13), textAlign: TextAlign.center)),
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
                onPressed: () => _previewPdf(context, invoice),
                icon: const Icon(Iconsax.document, size: 18),
                label: const Text('PDF'),
              ),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _previewPdf(BuildContext context, Invoice invoice) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PdfPreviewPage(invoice: invoice),
      ),
    );
  }

  Future<void> _printPdf(BuildContext context, Invoice invoice) async {
    final pdf = await PdfService.generateInvoice(invoice);
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  Future<void> _sharePdf(BuildContext context, Invoice invoice) async {
    final pdf = await PdfService.generateInvoice(invoice);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${invoice.number}.pdf',
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
  const _PdfPreviewPage({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('PDF ${invoice.number}'),
      actions: [
        IconButton(
          icon: const Icon(Iconsax.share),
          onPressed: () async {
            final pdf = await PdfService.generateInvoice(invoice);
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
        final pdf = await PdfService.generateInvoice(invoice);
        return pdf.save();
      },
      canChangeOrientation: false,
      canChangePageFormat: false,
      pdfFileName: '${invoice.number}.pdf',
    ),
  );
}
