import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/models/tax_profile.dart';
import '../../../core/providers/tax_profile_provider.dart';
import '../../../core/theme/app_theme.dart';

class TaxProfileScreen extends ConsumerStatefulWidget {
  const TaxProfileScreen({super.key});

  @override
  ConsumerState<TaxProfileScreen> createState() => _TaxProfileScreenState();
}

class _TaxProfileScreenState extends ConsumerState<TaxProfileScreen> {
  TaxProfile? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(taxProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Налоговый профиль'),
      ),
      body: asyncProfile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (loaded) {
          final p = _draft ?? loaded;
          return _Form(
            profile: p,
            saving: _saving,
            onChange: (next) => setState(() => _draft = next),
            onSave: () => _save(p),
          );
        },
      ),
    );
  }

  Future<void> _save(TaxProfile p) async {
    setState(() => _saving = true);
    try {
      await ref.read(taxProfileProvider.notifier).save(p);
      if (mounted) {
        setState(() => _draft = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль сохранён. Теперь подсказки по КБК будут точнее.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: EsepColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Form ─────────────────────────────────────────────────────────────────────

class _Form extends StatelessWidget {
  const _Form({
    required this.profile,
    required this.saving,
    required this.onChange,
    required this.onSave,
  });

  final TaxProfile profile;
  final bool saving;
  final void Function(TaxProfile) onChange;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Зачем заполнять
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EsepColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EsepColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(children: [
            Icon(Iconsax.info_circle, color: EsepColors.primary, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Этот профиль помогает Esep подсказывать правильный КБК при оплате '
              'налогов и не пропустить ошибку до того, как платёж уйдёт в банк.',
              style: TextStyle(fontSize: 12, height: 1.5),
            )),
          ]),
        ),
        const SizedBox(height: 16),

        // Тип субъекта
        const _SectionHeader(title: 'Тип субъекта'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: EntityType.values.map((t) {
            return RadioListTile<EntityType>(
              title: Text(t.label),
              subtitle: Text(_entityHint(t),
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              value: t,
              groupValue: profile.entityType,
              onChanged: (v) {
                if (v == null) return;
                // При смене типа сбрасываем некоторые поля
                onChange(profile.copyWith(
                  entityType: v,
                  sizeCategory: v == EntityType.ip ? SizeCategory.small : profile.sizeCategory,
                ));
              },
            );
          }).toList()),
        ),
        const SizedBox(height: 16),

        // Налоговый режим
        const _SectionHeader(title: 'Налоговый режим'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: TaxRegimeKind.values.map((r) {
            return RadioListTile<TaxRegimeKind?>(
              title: Text(r.label),
              subtitle: Text(_regimeHint(r),
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              value: r,
              groupValue: profile.regime,
              onChanged: (v) => onChange(profile.copyWith(regime: v)),
            );
          }).toList()),
        ),
        const SizedBox(height: 16),

        // Размер бизнеса (только для ТОО)
        if (profile.entityType == EntityType.too) ...[
          const _SectionHeader(title: 'Размер бизнеса'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'По Закону «О предпринимательстве» РК ст. 24. От размера зависит КБК для КПН.',
              style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(children: SizeCategory.values.map((s) {
              return RadioListTile<SizeCategory>(
                title: Text(s.label),
                subtitle: Text(s.description,
                    style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                value: s,
                groupValue: profile.sizeCategory,
                onChanged: (v) => onChange(profile.copyWith(sizeCategory: v)),
              );
            }).toList()),
          ),
          const SizedBox(height: 16),
        ],

        // Сотрудники и НДС
        const _SectionHeader(title: 'Дополнительные параметры'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Есть сотрудники'),
              subtitle: const Text(
                'Влияет на: социальный налог, ИПН с зарплат, ОПВ/СО/ВОСМС за работников',
                style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
              ),
              value: profile.hasEmployees,
              onChanged: (v) => onChange(profile.copyWith(hasEmployees: v)),
            ),
            const Divider(height: 0),
            SwitchListTile(
              title: const Text('Я плательщик НДС'),
              subtitle: const Text(
                'Включается автоматически при превышении 10 000 МРП оборота',
                style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
              ),
              value: profile.isVatPayer,
              onChanged: (v) => onChange(profile.copyWith(isVatPayer: v)),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Подсказка результата
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EsepColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Iconsax.tick_circle, size: 16, color: EsepColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Ваш профиль: ${profile.humanLabel}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: saving
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Iconsax.tick_circle, size: 18),
            label: const Text('Сохранить профиль'),
            onPressed: saving ? null : onSave,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  String _entityHint(EntityType t) {
    switch (t) {
      case EntityType.ip:         return 'Индивидуальный предприниматель';
      case EntityType.too:        return 'Юридическое лицо (ТОО, АО и т.п.)';
      case EntityType.individual: return 'Физическое лицо без регистрации';
    }
  }

  String _regimeHint(TaxRegimeKind r) {
    switch (r) {
      case TaxRegimeKind.esp:           return '1 МРП в городе, 0.5 МРП в селе';
      case TaxRegimeKind.selfEmployed:  return '4% от дохода, лимит 3 600 МРП/год';
      case TaxRegimeKind.simplified910: return '4% от дохода, отчёт раз в полугодие';
      case TaxRegimeKind.general:       return 'ИПН 10/15% или КПН 20%, без лимита';
      case TaxRegimeKind.retail:        return 'Розничный налог (с 2026)';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: EsepColors.textSecondary,
        ),
      ),
    );
  }
}
