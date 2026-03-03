import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/invoice.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/services/esf_service.dart';
import 'esf_download_stub.dart'
    if (dart.library.html) 'esf_download_web.dart' as downloader;

class EsfPreviewScreen extends ConsumerWidget {
  const EsfPreviewScreen({super.key, required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companyProvider);
    final xml = EsfService.generate(invoice, company);

    return Scaffold(
      appBar: AppBar(
        title: Text('ЭСФ ${invoice.number}'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.copy),
            tooltip: 'Скопировать XML',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: xml));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('XML скопирован в буфер обмена')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Iconsax.document_download),
            tooltip: 'Скачать XML',
            onPressed: () => _download(context, invoice, xml),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Warning banner
          if (!company.isComplete)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EsepColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EsepColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Iconsax.warning_2, color: EsepColors.warning, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Заполните данные вашей компании в Настройках для корректного ЭСФ',
                    style: TextStyle(fontSize: 12, color: EsepColors.warning),
                  ),
                ),
              ]),
            ),

          // Info row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Icon(Iconsax.info_circle, size: 14, color: EsepColors.textSecondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Загрузите XML на портал esf.gov.kz → Импорт ЭСФ',
                  style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),

          // XML viewer
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  xml,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: Color(0xFFCDD6F4),
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // Bottom bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: xml));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Скопировано')),
                      );
                    },
                    icon: const Icon(Iconsax.copy, size: 18),
                    label: const Text('Копировать'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _download(context, invoice, xml),
                    icon: const Icon(Iconsax.document_download, size: 18),
                    label: const Text('Скачать .xml'),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _download(BuildContext context, Invoice invoice, String xml) {
    try {
      final bytes = utf8.encode(xml);
      final filename = 'esf-${invoice.number}.xml';
      downloader.downloadFile(bytes: bytes, filename: filename, mimeType: 'application/xml');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Файл $filename скачан')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Скачивание недоступно: $e'),
          backgroundColor: EsepColors.expense,
        ),
      );
    }
  }
}
