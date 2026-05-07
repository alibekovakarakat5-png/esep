// PageGuideCard — компактная объяснялка вверху экрана для ИП и бухгалтеров.
// Зачем: малый бизнес часто не понимает с первого взгляда зачем тут эта вкладка
// и какой результат она даёт. Эта карточка в одном виде даёт:
//   • что это за раздел («Что это и зачем»),
//   • что вы можете сделать (буллеты),
//   • какой результат получите.
//
// Один раз закрыл → больше не показывается на этом устройстве (по [id]).
// Если хочется заново — почистить SharedPreferences или сменить id.

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PageGuideCard extends StatefulWidget {
  /// Уникальный идентификатор экрана. По нему запоминаем «свернул».
  final String id;

  /// Иконка слева (iconsax / Material). Если null — взяли Iconsax.info_circle.
  final IconData? icon;

  /// Заголовок («Налоги ИП — за что и сколько платить»).
  final String title;

  /// 1-2 предложения общего описания.
  final String description;

  /// До 6 буллетов «что вы можете сделать здесь».
  final List<String> whatYouCanDo;

  /// Главный результат («Закроете 910 за 5 минут без бухгалтера»).
  final String? outcome;

  /// Дополнительный CTA-блок (необязательно).
  final String? ctaLabel;
  final VoidCallback? onCta;

  const PageGuideCard({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    this.icon,
    this.whatYouCanDo = const [],
    this.outcome,
    this.ctaLabel,
    this.onCta,
  });

  @override
  State<PageGuideCard> createState() => _PageGuideCardState();
}

class _PageGuideCardState extends State<PageGuideCard> {
  bool _hidden = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hidden = prefs.getBool(_storageKey) ?? false;
      _ready = true;
    });
  }

  String get _storageKey => 'pageGuide.${widget.id}.dismissed';

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey, true);
    if (mounted) setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _hidden) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Лёгкий tint без дешёвых градиентов: соответствует стилю Esep.
    final bg = isLight
        ? cs.primaryContainer.withValues(alpha: 0.30)
        : cs.primaryContainer.withValues(alpha: 0.16);
    final border = cs.primary.withValues(alpha: 0.20);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Иконка
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              widget.icon ?? Iconsax.info_circle,
              color: cs.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // Контент
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'ЧТО ЭТО И ЗАЧЕМ',
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
                if (widget.whatYouCanDo.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...widget.whatYouCanDo.map((line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6, right: 8),
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(fontSize: 12.5, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
                if (widget.outcome != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Iconsax.tick_circle, size: 16, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.outcome!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.ctaLabel != null && widget.onCta != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onCta,
                      icon: const Icon(Iconsax.arrow_right_3, size: 16),
                      label: Text(widget.ctaLabel!),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
