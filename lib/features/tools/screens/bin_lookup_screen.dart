import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';

class BinLookupScreen extends ConsumerWidget {
  const BinLookupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск по БИН')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: EsepColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Iconsax.building_4,
                  size: 40,
                  color: EsepColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Поиск по БИН',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: EsepColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Мы подключаем партнёрский API для поиска\n'
                'компаний по БИН — название, руководитель,\n'
                'адрес, вид деятельности.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: EsepColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: EsepColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Iconsax.timer_1, size: 20, color: EsepColors.warning),
                    SizedBox(width: 10),
                    Text(
                      'Скоро будет доступно',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: EsepColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

