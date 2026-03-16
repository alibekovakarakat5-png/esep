import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/user_mode_provider.dart';

class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // ── Header ───────────────────────────────────────────────────
              const Text(
                'Есеп',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: EsepColors.primary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Кто вы?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: EsepColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Выберите режим — интерфейс подстроится\nпод ваши задачи',
                style: TextStyle(
                  fontSize: 14,
                  color: EsepColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),

              // ── ИП card ──────────────────────────────────────────────────
              _ModeCard(
                mode: UserMode.ip,
                icon: Iconsax.user_square,
                title: 'Индивидуальный предприниматель',
                subtitle: 'Веду свой бизнес',
                color: EsepColors.primary,
                features: const [
                  (Iconsax.wallet_2,    'Доходы и расходы'),
                  (Iconsax.receipt_2,   'Счета клиентам'),
                  (Iconsax.calculator,  'Калькулятор налогов'),
                  (Iconsax.people,      'База контрагентов'),
                ],
                onTap: () => _select(context, ref, UserMode.ip),
              ),
              const SizedBox(height: 14),

              // ── Бухгалтер card ───────────────────────────────────────────
              _ModeCard(
                mode: UserMode.accountant,
                icon: Iconsax.briefcase,
                title: 'Бухгалтер',
                subtitle: 'Веду нескольких клиентов',
                color: const Color(0xFF7B2FBE),
                features: const [
                  (Iconsax.people,        'ИП и ТОО под управлением'),
                  (Iconsax.calendar_1,    'Единый календарь дедлайнов'),
                  (Iconsax.document_text, 'Чеклисты документов'),
                  (Iconsax.money_send,    'Расчёт ФОТ и соцплатежей'),
                ],
                onTap: () => _select(context, ref, UserMode.accountant),
              ),

              const Spacer(),

              // ── Footer ───────────────────────────────────────────────────
              const Center(
                child: Text(
                  'Режим можно сменить в Настройках',
                  style: TextStyle(fontSize: 12, color: EsepColors.textDisabled),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, WidgetRef ref, UserMode mode) {
    ref.read(userModeProvider.notifier).set(mode);
    context.go(mode == UserMode.ip ? '/dashboard' : '/accountant');
  }
}

// ── Mode Card ─────────────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.features,
    required this.onTap,
  });

  final UserMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<(IconData, String)> features;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon + title
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: EsepColors.textSecondary)),
                ]),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
            ]),

            const SizedBox(height: 16),

            // Feature chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: features.map((f) => _FeatureChip(
                icon: f.$1,
                label: f.$2,
                color: color,
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    ]),
  );
}
