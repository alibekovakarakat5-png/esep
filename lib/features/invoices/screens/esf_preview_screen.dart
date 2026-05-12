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
    final validation = EsfService.validate(invoice, company);
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
            onPressed: validation.isValid
                ? () => _download(context, invoice, xml)
                : () => _showBlockedSnack(context, validation),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Errors banner — блокируют скачивание
          if (validation.errors.isNotEmpty)
            _IssueBanner(
              icon: Iconsax.close_square,
              color: EsepColors.expense,
              title: 'XML не пройдёт импорт на esf.gov.kz',
              items: validation.errors,
            ),

          // Warnings banner — мягкие предупреждения
          if (validation.warnings.isNotEmpty)
            _IssueBanner(
              icon: Iconsax.warning_2,
              color: EsepColors.warning,
              title: 'Возможные проблемы',
              items: validation.warnings,
            ),

          // VAT badge
          if (company.isVatPayer)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: EsepColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.percent, size: 14, color: EsepColors.primary),
                SizedBox(width: 6),
                Text(
                  'Плательщик НДС — добавлен 16% сверху',
                  style: TextStyle(fontSize: 12, color: EsepColors.primary, fontWeight: FontWeight.w600),
                ),
              ]),
            ),

          // Info row
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Icon(Iconsax.info_circle, size: 14, color: EsepColors.textSecondary),
              SizedBox(width: 6),
              Expanded(
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
                    onPressed: validation.isValid
                        ? () => _download(context, invoice, xml)
                        : () => _showBlockedSnack(context, validation),
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

  void _showBlockedSnack(BuildContext context, EsfValidation validation) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Исправьте ошибки перед скачиванием: ${validation.errors.first}',
        ),
        backgroundColor: EsepColors.expense,
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

class _IssueBanner extends StatelessWidget {
  const _IssueBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(
                  '• $it',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              )),
        ],
      ),
    );
  }
}
