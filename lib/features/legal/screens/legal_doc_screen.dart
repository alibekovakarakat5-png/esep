import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants/legal_docs.dart';
import '../../../core/theme/app_theme.dart';

class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({super.key, required this.type});
  final LegalDocType type;

  @override
  Widget build(BuildContext context) {
    final sections = legalDocContent(type);

    return Scaffold(
      appBar: AppBar(title: Text(type.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            type.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Версия $legalDocsVersion · обновлено $legalDocsUpdatedAt',
            style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (type == LegalDocType.terms) const _TwoSidedIntroCard(),
          if (type == LegalDocType.terms) const SizedBox(height: 20),
          for (final s in sections) _SectionView(section: s),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'Это документ в простой форме. В случае противоречия с '
            'требованиями законодательства Республики Казахстан — '
            'применяется законодательство.',
            style: TextStyle(
              fontSize: 12,
              color: EsepColors.textSecondary,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка «Что делаем мы / Что делаете вы» — только для Условий.
class _TwoSidedIntroCard extends StatelessWidget {
  const _TwoSidedIntroCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: EsepColors.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Iconsax.shield_tick, color: EsepColors.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Работаем в команде',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ]),
            const SizedBox(height: 12),
            _ResponsibilityRow(
              icon: Iconsax.calculator,
              color: EsepColors.primary,
              title: 'Esep',
              bullets: [
                'Актуальные ставки и формулы НК РК',
                'Расчёт налогов по вашим данным',
                'Экспорт декларации и напоминания',
                'Конфиденциальность ваших данных',
              ],
            ),
            const SizedBox(height: 12),
            _ResponsibilityRow(
              icon: Iconsax.user_octagon,
              color: EsepColors.income,
              title: 'Вы',
              bullets: [
                'Полнота введённых данных',
                'Проверка декларации перед подачей',
                'Подача и оплата в КГД в срок',
                'Финальная ответственность — по закону',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsibilityRow extends StatelessWidget {
  const _ResponsibilityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.bullets,
  });
  final IconData icon;
  final Color color;
  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              for (final b in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                            fontSize: 13,
                            color: EsepColors.textSecondary,
                          )),
                      Expanded(
                        child: Text(
                          b,
                          style: const TextStyle(
                            fontSize: 13,
                            color: EsepColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});
  final LegalDocSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.heading,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: EsepColors.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: const TextStyle(
              fontSize: 14,
              color: EsepColors.textPrimary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
