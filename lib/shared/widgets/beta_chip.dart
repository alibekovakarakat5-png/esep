import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Маленький бейдж «бета» — честно помечает новые/тестируемые фичи,
/// чтобы пользователь понимал, что функция свежая (напр. дебиторка, авто-сверка).
class BetaChip extends StatelessWidget {
  const BetaChip({super.key, this.label = 'бета'});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: EsepColors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: EsepColors.warning.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: EsepColors.warning,
            letterSpacing: 0.3,
          ),
        ),
      );
}
