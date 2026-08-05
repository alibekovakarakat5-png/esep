/// FirstRunScreen — «Начало работы» после первого входа.
///
/// Почему он существует: на проде было 14 зарегистрированных пользователей и
/// НОЛЬ операций, счетов и платежей. Люди доходили до дашборда и упирались в
/// четыре баннера и пустые графики — непонятно, с чего начать. Здесь на каждом
/// экране РОВНО ОДНО действие и всегда видимая кнопка «пропустить».
///
/// Три шага:
///   1. Загрузить выписку   → главный шаг активации (данные в приложении)
///   2. Режим налогообложения → один тап, нужен для расчёта
///   3. Готово               → куда идти дальше
///
/// Показывается один раз, флаг в Hive `first_run_done`. Для режима
/// «бухгалтер» не показывается — у него другой первый шаг (клиенты).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/models/tax_profile.dart';
import '../../../core/providers/tax_profile_provider.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/responsive_form_shell.dart';
import '../../transactions/screens/kaspi_import_screen.dart';

/// Прошёл ли пользователь «Начало работы».
final firstRunDoneProvider = StateProvider<bool>((ref) {
  return Hive.box('settings').get('first_run_done', defaultValue: false) as bool;
});

void markFirstRunDone(WidgetRef ref) {
  final box = Hive.box('settings');
  box.put('first_run_done', true);
  // Старый баннер-тур на дашборде объяснял то же самое. Прошёл «Начало
  // работы» — второй раз показывать нечего, иначе баннеры копятся.
  box.put('dashboard_tour_done', true);
  ref.read(firstRunDoneProvider.notifier).state = true;
}

class FirstRunScreen extends ConsumerStatefulWidget {
  const FirstRunScreen({super.key});

  @override
  ConsumerState<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends ConsumerState<FirstRunScreen> {
  int _step = 0;
  static const _totalSteps = 3;

  /// Загрузил ли выписку на шаге 1 (для итогового экрана).
  bool _imported = false;
  TaxRegimeKind? _pickedRegime;

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _finish() {
    markFirstRunDone(ref);
    context.go('/dashboard');
  }

  /// Шаг 1 — открыть импорт выписки. KaspiImportScreen кладём обычным
  /// MaterialPageRoute (как это делает BankConnectScreen), чтобы после
  /// импорта пользователь вернулся сюда, а не улетел в раздел с нижним меню.
  Future<void> _openImport() async {
    final before = ref.read(transactionProvider).length;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KaspiImportScreen()),
    );
    if (!mounted) return;
    final after = ref.read(transactionProvider).length;
    setState(() => _imported = after > before);
    _next();
  }

  /// Шаг 2 — сохранить режим. Сеть может отвалиться: онбординг не должен
  /// на этом останавливаться, режим всегда можно поменять в настройках.
  Future<void> _pickRegime(TaxRegimeKind regime) async {
    setState(() => _pickedRegime = regime);
    final async = ref.read(taxProfileProvider);
    final current = async.valueOrNull ??
        const TaxProfile(entityType: EntityType.ip);
    try {
      await ref
          .read(taxProfileProvider.notifier)
          .save(current.copyWith(regime: regime));
    } catch (_) {
      // молча — режим не критичен для продолжения
    }
    if (!mounted) return;
    _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EsepColors.cardLight,
      body: ResponsiveFormShell(
        maxHeight: 720,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgressDots(step: _step, total: _totalSteps),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: switch (_step) {
                    0 => _StepStatement(
                        onImport: _openImport,
                        onSkip: _next,
                      ),
                    1 => _StepRegime(
                        picked: _pickedRegime,
                        onPick: _pickRegime,
                        onSkip: _next,
                      ),
                    _ => _StepDone(
                        imported: _imported,
                        regime: _pickedRegime,
                        onFinish: _finish,
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Прогресс ─────────────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Шаг ${step + 1} из $total',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: EsepColors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: List.generate(total, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: i <= step ? EsepColors.primary : EsepColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// Общая шапка шага: иконка, заголовок, пояснение. Одна на все шаги,
/// чтобы шаги выглядели одинаково и не разъезжались.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 30, color: color),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: EsepColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: EsepColors.textSecondary,
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// Кнопка «пропустить» — всегда одинаковая и всегда видимая.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        foregroundColor: EsepColors.textSecondary,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ── Шаг 1 — выписка ──────────────────────────────────────────────────────────

class _StepStatement extends StatelessWidget {
  const _StepStatement({required this.onImport, required this.onSkip});
  final VoidCallback onImport;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          icon: Iconsax.document_upload,
          color: EsepColors.primary,
          title: 'Загрузите выписку\nиз банка',
          subtitle: 'Esep сам разнесёт доходы и расходы и посчитает налог. '
              'Вручную вбивать операции не нужно.',
        ),
        const _FactRow(
          icon: Iconsax.bank,
          text: 'Kaspi, Halyk, Jusan, Forte, Bereke — и другие банки',
        ),
        const SizedBox(height: 12),
        const _FactRow(
          icon: Iconsax.document_text,
          text: 'Форматы Excel и CSV. Колонки распознаются автоматически',
        ),
        const SizedBox(height: 12),
        const _FactRow(
          icon: Iconsax.calendar_1,
          text: 'Выписку берите за период с начала года',
        ),
        const SizedBox(height: 30),
        ElevatedButton.icon(
          onPressed: onImport,
          icon: const Icon(Iconsax.document_upload, size: 20),
          label: const Text('Выбрать файл выписки'),
        ),
        const SizedBox(height: 6),
        _SkipButton(label: 'Пропустить — внесу вручную', onTap: onSkip),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: EsepColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: EsepColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Шаг 2 — режим налогообложения ───────────────────────────────────────────

class _StepRegime extends StatelessWidget {
  const _StepRegime({
    required this.picked,
    required this.onPick,
    required this.onSkip,
  });

  final TaxRegimeKind? picked;
  final ValueChanged<TaxRegimeKind> onPick;
  final VoidCallback onSkip;

  static const _options = [
    (
      TaxRegimeKind.simplified910,
      'Упрощёнка (форма 910)',
      '4% с дохода, отчёт раз в полгода. Самый частый режим у ИП',
      Iconsax.chart_2,
    ),
    (
      TaxRegimeKind.selfEmployed,
      'Самозанятый',
      '4% с дохода, лимит 300 МРП в месяц. Без сотрудников',
      Iconsax.user,
    ),
    (
      TaxRegimeKind.general,
      'ОУР (общеустановленный)',
      '10% с прибыли, учёт расходов обязателен',
      Iconsax.building_4,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          icon: Iconsax.percentage_square,
          color: EsepColors.gold,
          title: 'На каком режиме\nвы работаете?',
          subtitle: 'От этого зависит, как Esep считает налог и какие формы '
              'напоминает сдать. Поменять можно в настройках.',
        ),
        for (final (regime, title, desc, icon) in _options) ...[
          _RegimeCard(
            icon: icon,
            title: title,
            description: desc,
            selected: picked == regime,
            onTap: () => onPick(regime),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        _SkipButton(label: 'Не знаю — определюсь позже', onTap: onSkip),
      ],
    );
  }
}

class _RegimeCard extends StatelessWidget {
  const _RegimeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? EsepColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? EsepColors.primary : EsepColors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? EsepColors.primary : EsepColors.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: EsepColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: EsepColors.textSecondary,
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

// ── Шаг 3 — готово ───────────────────────────────────────────────────────────

class _StepDone extends StatelessWidget {
  const _StepDone({
    required this.imported,
    required this.regime,
    required this.onFinish,
  });

  final bool imported;
  final TaxRegimeKind? regime;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Iconsax.tick_circle,
          color: EsepColors.income,
          title: imported ? 'Готово — данные\nв приложении' : 'Готово',
          subtitle: imported
              ? 'Дальше всё считается само. Загляните в «Налоги» — там уже '
                  'видно, сколько платить и до какого числа.'
              : 'Загрузить выписку можно в любой момент — раздел «Операции», '
                  'кнопка «Загрузить из банка».',
        ),
        _DoneRow(done: imported, text: 'Выписка загружена'),
        const SizedBox(height: 12),
        _DoneRow(
          done: regime != null,
          text: regime != null
              ? 'Режим: ${regime!.label}'
              : 'Режим налогообложения не указан',
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: onFinish,
          child: const Text('Перейти в Esep'),
        ),
      ],
    );
  }
}

class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.done, required this.text});
  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          done ? Iconsax.tick_circle : Iconsax.minus_cirlce,
          size: 20,
          color: done ? EsepColors.income : EsepColors.textDisabled,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: done ? FontWeight.w600 : FontWeight.w400,
              color: done ? EsepColors.textPrimary : EsepColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
