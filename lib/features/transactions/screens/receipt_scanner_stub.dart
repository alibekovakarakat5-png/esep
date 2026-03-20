import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';

class ReceiptScannerScreen extends StatelessWidget {
  const ReceiptScannerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Сканер чеков')),
        body: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Iconsax.scan, size: 64, color: EsepColors.textDisabled),
            SizedBox(height: 16),
            Text('Доступно только в мобильном приложении',
                style: TextStyle(fontSize: 16, color: EsepColors.textSecondary)),
            SizedBox(height: 8),
            Text('Скачайте Esep для Android чтобы\nсканировать чеки камерой',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: EsepColors.textDisabled)),
          ]),
        ),
      );
}
