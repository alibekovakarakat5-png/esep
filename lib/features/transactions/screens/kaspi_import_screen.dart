import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/kaspi_parser.dart';
import '../../../core/services/category_memory.dart';
import '../../../core/providers/transaction_provider.dart';

class KaspiImportScreen extends ConsumerStatefulWidget {
  const KaspiImportScreen({super.key});

  @override
  ConsumerState<KaspiImportScreen> createState() => _KaspiImportScreenState();
}

class _KaspiImportScreenState extends ConsumerState<KaspiImportScreen> {
  KaspiParseResult? _result;
  bool _loading = false;
  String? _fileName;
  bool _importing = false;

  /// Режим массового выбора
  bool _multiSelectMode = false;
  final Set<int> _multiSelected = {};

  final _fmt = NumberFormat('#,##0', 'ru_RU');
  final _dateFmt = DateFormat('dd.MM.yyyy');

  Future<void> _pickFile() async {
    setState(() => _loading = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _loading = false;
        });
        _showError('Не удалось прочитать файл');
        return;
      }

      final result = KaspiParser.parseFile(bytes, file.name);

      // Auto-assign categories from memory, then fallback to autoCategory
      for (final row in result.rows) {
        final remembered =
            CategoryMemory.recall(row.description, row.counterparty);
        if (remembered != null) {
          row.category = remembered;
        } else {
          row.category =
              KaspiParser.autoCategory(row.description, row.isIncome);
        }
      }

      setState(() {
        _result = result;
        _fileName = file.name;
        _loading = false;
        _multiSelectMode = false;
        _multiSelected.clear();
      });

      if (result.warnings.isNotEmpty) {
        _showWarnings(result.warnings);
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Ошибка: $e');
    }
  }

  Future<void> _importSelected() async {
    final result = _result;
    if (result == null) return;

    final selected = result.rows.where((r) => r.selected).toList();
    if (selected.isEmpty) {
      _showError('Нет выбранных транзакций');
      return;
    }

    setState(() => _importing = true);

    final notifier = ref.read(transactionProvider.notifier);
    for (final row in selected) {
      final category =
          row.category ?? KaspiParser.autoCategory(row.description, row.isIncome);

      await notifier.add(
        title: row.description,
        amount: row.amount,
        isIncome: row.isIncome,
        date: row.date,
        clientName: row.counterparty,
        source: 'kaspi',
        category: category,
      );

      // Remember the category for future imports
      await CategoryMemory.remember(
          row.description, row.counterparty, category);
    }

    setState(() => _importing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Импортировано ${selected.length} транзакций'),
          backgroundColor: EsepColors.income,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: EsepColors.expense),
    );
  }

  void _showWarnings(List<String> warnings) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Предупреждения'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: warnings
              .map((w) =>
                  Text('• $w', style: const TextStyle(fontSize: 13)))
              .toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ок')),
        ],
      ),
    );
  }

  void _selectAll(bool value) {
    setState(() {
      for (final row in _result!.rows) {
        row.selected = value;
      }
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) {
        _multiSelected.clear();
      }
    });
  }

  void _toggleMultiSelect(int index) {
    setState(() {
      if (_multiSelected.contains(index)) {
        _multiSelected.remove(index);
      } else {
        _multiSelected.add(index);
      }
    });
  }

  void _showCategoryPicker(int rowIndex) {
    final row = _result!.rows[rowIndex];
    _showCategorySheet(
      currentCategory: row.category,
      onSelected: (cat) {
        setState(() {
          row.category = cat;
        });
      },
    );
  }

  void _showMassCategoryPicker() {
    if (_multiSelected.isEmpty) {
      _showError('Выберите строки для назначения категории');
      return;
    }
    _showCategorySheet(
      currentCategory: null,
      onSelected: (cat) {
        setState(() {
          for (final idx in _multiSelected) {
            _result!.rows[idx].category = cat;
          }
          _multiSelected.clear();
          _multiSelectMode = false;
        });
      },
    );
  }

  void _showCategorySheet({
    required String? currentCategory,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: EsepColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Выберите категорию',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: CategoryMemory.allCategories.map((cat) {
                  final isSelected = cat == currentCategory;
                  return ListTile(
                    leading: Icon(
                      _categoryIcon(cat),
                      color: isSelected
                          ? EsepColors.primary
                          : EsepColors.textSecondary,
                      size: 22,
                    ),
                    title: Text(cat,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? EsepColors.primary
                              : EsepColors.textPrimary,
                        )),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: EsepColors.primary,
                            size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(cat);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static IconData _categoryIcon(String category) {
    return switch (category) {
      'Доход' => Iconsax.money_recive,
      'Оплата услуг' => Iconsax.receipt_item,
      'Перевод' => Iconsax.arrow_swap_horizontal,
      'Возврат' => Iconsax.rotate_left,
      'Налоги' => Iconsax.judge,
      'Аренда' => Iconsax.home_2,
      'Зарплата' => Iconsax.people,
      'Коммунальные' => Iconsax.flash_circle,
      'Связь' => Iconsax.call,
      'Реклама' => Iconsax.volume_high,
      'Транспорт' => Iconsax.car,
      'Офис' => Iconsax.briefcase,
      'Прочее' => Iconsax.more_circle,
      _ => Iconsax.tag,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_multiSelectMode
            ? 'Выбрано: ${_multiSelected.length}'
            : 'Импорт Kaspi'),
        leading: _multiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleMultiSelectMode,
              )
            : null,
        actions: [
          if (_result != null && _result!.rows.isNotEmpty) ...[
            if (!_multiSelectMode)
              IconButton(
                icon: const Icon(Iconsax.task_square),
                tooltip: 'Массовое назначение',
                onPressed: _toggleMultiSelectMode,
              ),
            if (_multiSelectMode)
              TextButton.icon(
                onPressed:
                    _multiSelected.isEmpty ? null : _showMassCategoryPicker,
                icon: const Icon(Iconsax.category, size: 18),
                label: const Text('Категория'),
              ),
            if (!_multiSelectMode)
              TextButton(
                onPressed: _importing ? null : _importSelected,
                child: _importing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Импортировать',
                        style: TextStyle(
                            color: EsepColors.primary,
                            fontWeight: FontWeight.w600)),
              ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: _result == null ? _buildEmptyState() : _buildPreview(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: EsepColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Iconsax.document_upload,
                  color: EsepColors.primary, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Импорт выписки Kaspi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Поддерживаются выписки Kaspi Gold, Kaspi Business, Halyk и Forte '
              'в форматах Excel (.xlsx) и CSV. '
              'Скачайте выписку в личном кабинете банка.',
              style:
                  TextStyle(fontSize: 13, color: EsepColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildFormatHint(),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Iconsax.folder_open),
              label: Text(_loading ? 'Загрузка...' : 'Выбрать файл'),
            ),
            const SizedBox(height: 12),
            const Text('Поддерживаются .xlsx, .csv, .txt',
                style: TextStyle(
                    fontSize: 12, color: EsepColors.textDisabled)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatHint() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EsepColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: EsepColors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Iconsax.info_circle, color: EsepColors.info, size: 16),
              SizedBox(width: 8),
              Text('Как скачать выписку',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: EsepColors.info)),
            ]),
            const SizedBox(height: 8),
            _hintLine(
                'Kaspi Business', 'Личный кабинет → Счета → Выписка → Excel'),
            _hintLine(
                'Kaspi Gold', 'Приложение → Мой банк → Выписка → Экспорт'),
            _hintLine('Halyk / Forte', 'Онлайн-банк → Счета → Выписка → XLS'),
          ]),
    );
  }

  Widget _hintLine(String app, String path) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('• ',
              style:
                  TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          Expanded(
              child: RichText(
                  text: TextSpan(
            style: const TextStyle(
                fontSize: 12, color: EsepColors.textSecondary),
            children: [
              TextSpan(
                  text: '$app: ',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: EsepColors.textPrimary)),
              TextSpan(text: path),
            ],
          ))),
        ]),
      );

  Widget _buildPreview() {
    final result = _result!;
    final selectedCount = result.rows.where((r) => r.selected).length;

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: EsepColors.cardLight,
            border:
                Border(bottom: BorderSide(color: EsepColors.divider)),
          ),
          child: Column(children: [
            // File info
            Row(children: [
              const Icon(Iconsax.document_text,
                  size: 16, color: EsepColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _fileName ?? 'файл',
                  style: const TextStyle(
                      fontSize: 12, color: EsepColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatLabel(result.format),
                style: const TextStyle(
                    fontSize: 11,
                    color: EsepColors.primary,
                    fontWeight: FontWeight.w600),
              ),
            ]),
            const SizedBox(height: 10),
            // Stats chips
            Row(children: [
              _StatChip(
                label: 'Доходов',
                value: '${result.incomeCount}',
                sub: '${_fmt.format(result.totalIncome)} ₸',
                color: EsepColors.income,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Расходов',
                value: '${result.expenseCount}',
                sub: '${_fmt.format(result.totalExpense)} ₸',
                color: EsepColors.expense,
              ),
              const Spacer(),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        'Выбрано: $selectedCount из ${result.rows.length}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    Row(children: [
                      TextButton(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        onPressed: () => _selectAll(true),
                        child: const Text('Все',
                            style: TextStyle(fontSize: 11)),
                      ),
                      const Text(' / ',
                          style: TextStyle(
                              fontSize: 11,
                              color: EsepColors.textDisabled)),
                      TextButton(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        onPressed: () => _selectAll(false),
                        child: const Text('Ни одного',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                  ]),
            ]),
          ]),
        ),

        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: result.rows.length,
            itemBuilder: (_, i) {
              final isMultiSelected = _multiSelected.contains(i);
              return _RowTile(
                row: result.rows[i],
                fmt: _fmt,
                dateFmt: _dateFmt,
                multiSelectMode: _multiSelectMode,
                isMultiSelected: isMultiSelected,
                onToggleSelected: (v) =>
                    setState(() => result.rows[i].selected = v),
                onToggleType: () => setState(
                    () => result.rows[i].isIncome = !result.rows[i].isIncome),
                onTapCategory: () => _showCategoryPicker(i),
                onMultiSelectTap: () => _toggleMultiSelect(i),
              );
            },
          ),
        ),

        // Bottom action
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _multiSelectMode
                ? Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _multiSelected.clear();
                            for (int i = 0;
                                i < _result!.rows.length;
                                i++) {
                              _multiSelected.add(i);
                            }
                          });
                        },
                        child: const Text('Выбрать все'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _multiSelected.isEmpty
                            ? null
                            : _showMassCategoryPicker,
                        icon: const Icon(Iconsax.category, size: 18),
                        label: Text(
                            'Категория (${_multiSelected.length})'),
                      ),
                    ),
                  ])
                : Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _pickFile,
                        icon: const Icon(Iconsax.folder_open, size: 18),
                        label: const Text('Другой файл'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: (_importing || selectedCount == 0)
                            ? null
                            : _importSelected,
                        icon: _importing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Iconsax.import, size: 18),
                        label: Text(_importing
                            ? 'Импорт...'
                            : 'Импортировать ($selectedCount)'),
                      ),
                    ),
                  ]),
          ),
        ),
      ],
    );
  }

  String _formatLabel(String fmt) {
    return switch (fmt) {
      'kaspi_gold' => 'Kaspi Gold',
      'kaspi_business' => 'Kaspi Business',
      'generic' => 'Банковская выписка',
      _ => 'Авто',
    };
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label,
      required this.value,
      required this.sub,
      required this.color});
  final String label, value, sub;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color)),
          Text(sub,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.7))),
        ]),
      );
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.fmt,
    required this.dateFmt,
    required this.onToggleSelected,
    required this.onToggleType,
    required this.onTapCategory,
    required this.multiSelectMode,
    required this.isMultiSelected,
    required this.onMultiSelectTap,
  });

  final KaspiRow row;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback onToggleType;
  final VoidCallback onTapCategory;
  final bool multiSelectMode;
  final bool isMultiSelected;
  final VoidCallback onMultiSelectTap;

  @override
  Widget build(BuildContext context) {
    final color = row.isIncome ? EsepColors.income : EsepColors.expense;
    final sign = row.isIncome ? '+' : '-';

    return GestureDetector(
      onTap: multiSelectMode ? onMultiSelectTap : null,
      child: Opacity(
        opacity: multiSelectMode
            ? (isMultiSelected ? 1.0 : 0.5)
            : (row.selected ? 1.0 : 0.4),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: multiSelectMode && isMultiSelected
                ? EsepColors.primary.withValues(alpha: 0.06)
                : EsepColors.cardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: multiSelectMode && isMultiSelected
                  ? EsepColors.primary.withValues(alpha: 0.4)
                  : EsepColors.divider,
            ),
          ),
          child: Column(
            children: [
              Row(children: [
                // Checkbox or multi-select indicator
                if (multiSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      isMultiSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isMultiSelected
                          ? EsepColors.primary
                          : EsepColors.textDisabled,
                      size: 22,
                    ),
                  )
                else
                  Checkbox(
                    value: row.selected,
                    onChanged: (v) => onToggleSelected(v ?? false),
                    activeColor: EsepColors.primary,
                    side: const BorderSide(color: EsepColors.textDisabled),
                  ),

                // Type indicator
                GestureDetector(
                  onTap: multiSelectMode ? null : onToggleType,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      row.isIncome
                          ? Iconsax.arrow_circle_up
                          : Iconsax.arrow_circle_down,
                      color: color,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Description + date + counterparty
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          row.description,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (row.counterparty != null)
                          Text(
                            row.counterparty!,
                            style: const TextStyle(
                                fontSize: 11,
                                color: EsepColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          dateFmt.format(row.date),
                          style: const TextStyle(
                              fontSize: 11,
                              color: EsepColors.textDisabled),
                        ),
                        const SizedBox(height: 4),
                      ]),
                ),

                // Amount
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$sign${fmt.format(row.amount)} ₸',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ]),

              // Category chip
              if (!multiSelectMode)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 52, right: 12, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: onTapCategory,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _chipColor(row.category)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _chipColor(row.category)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _KaspiImportScreenState._categoryIcon(
                                  row.category ?? 'Прочее'),
                              size: 12,
                              color: _chipColor(row.category),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              row.category ?? 'Прочее',
                              style: TextStyle(
                                fontSize: 11,
                                color: _chipColor(row.category),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.edit,
                              size: 10,
                              color: _chipColor(row.category)
                                  .withValues(alpha: 0.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _chipColor(String? category) {
    return switch (category) {
      'Доход' => EsepColors.income,
      'Возврат' => EsepColors.income,
      'Налоги' => EsepColors.expense,
      'Зарплата' => EsepColors.warning,
      'Аренда' => EsepColors.info,
      'Коммунальные' => EsepColors.info,
      'Связь' => EsepColors.primary,
      'Реклама' => EsepColors.gold,
      'Транспорт' => EsepColors.textSecondary,
      'Офис' => EsepColors.textSecondary,
      _ => EsepColors.primary,
    };
  }
}
