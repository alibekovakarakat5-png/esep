import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import 'kaspi_import_screen.dart';

// ── Last sync state (persisted in Hive) ─────────────────────────────────────

class _BankSyncInfo {
  final String bankKey;
  final DateTime lastSync;
  final int transactionCount;

  _BankSyncInfo({required this.bankKey, required this.lastSync, required this.transactionCount});
}

_BankSyncInfo? _getSyncInfo(String bankKey) {
  final box = Hive.box('settings');
  final ts = box.get('bank_sync_${bankKey}_at') as String?;
  if (ts == null) return null;
  return _BankSyncInfo(
    bankKey: bankKey,
    lastSync: DateTime.parse(ts),
    transactionCount: box.get('bank_sync_${bankKey}_count', defaultValue: 0) as int,
  );
}

void saveSyncInfo(String bankKey, int count) {
  final box = Hive.box('settings');
  box.put('bank_sync_${bankKey}_at', DateTime.now().toIso8601String());
  box.put('bank_sync_${bankKey}_count', count);
}

// ── Bank data ───────────────────────────────────────────────────────────────

class _BankInfo {
  final String key;
  final String name;
  final String subtitle;
  final Color color;
  final IconData icon;
  final List<String> steps;

  const _BankInfo({
    required this.key,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.steps,
  });
}

const _banks = [
  _BankInfo(
    key: 'kaspi_business',
    name: 'Kaspi Business',
    subtitle: 'Для ИП и ТОО с бизнес-аккаунтом',
    color: Color(0xFFF14635),
    icon: Iconsax.shop,
    steps: [
      'Откройте my.kaspi.kz → Бизнес',
      'Выберите счёт → "Выписка"',
      'Укажите период → "Скачать Excel"',
      'Загрузите файл в Esep',
    ],
  ),
  _BankInfo(
    key: 'kaspi_gold',
    name: 'Kaspi Gold',
    subtitle: 'Для физлиц и ИП на Kaspi Gold',
    color: Color(0xFFF14635),
    icon: Iconsax.card,
    steps: [
      'Откройте приложение Kaspi.kz',
      'Мой банк → История → три точки (...)',
      '"Экспорт" → выберите период',
      'Сохраните файл → загрузите в Esep',
    ],
  ),
  _BankInfo(
    key: 'halyk',
    name: 'Halyk Bank',
    subtitle: 'Онлайн-банк Halyk для бизнеса',
    color: Color(0xFF00A859),
    icon: Iconsax.bank,
    steps: [
      'Войдите в online.halykbank.kz',
      'Счета → выберите счёт',
      '"Выписка" → укажите даты',
      'Скачайте CSV → загрузите в Esep',
    ],
  ),
  _BankInfo(
    key: 'forte',
    name: 'Forte Bank',
    subtitle: 'ForteBank онлайн-банкинг',
    color: Color(0xFF1A1A6C),
    icon: Iconsax.bank,
    steps: [
      'Войдите в online.forte.kz',
      'Счета → "Выписка по счёту"',
      'Укажите период → "Сформировать"',
      'Скачайте → загрузите в Esep',
    ],
  ),
];

// ── Screen ──────────────────────────────────────────────────────────────────

class BankConnectScreen extends ConsumerStatefulWidget {
  const BankConnectScreen({super.key});

  @override
  ConsumerState<BankConnectScreen> createState() => _BankConnectScreenState();
}

class _BankConnectScreenState extends ConsumerState<BankConnectScreen> {
  final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подключить банк')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  EsepColors.primary.withValues(alpha: 0.08),
                  EsepColors.primary.withValues(alpha: 0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: EsepColors.primary.withValues(alpha: 0.15)),
            ),
            child: const Row(children: [
              Icon(Iconsax.link_21, color: EsepColors.primary, size: 28),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Синхронизация с банком',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: EsepColors.textPrimary),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Выберите банк, скачайте выписку по инструкции — Esep распознает все транзакции автоматически',
                    style: TextStyle(fontSize: 13, color: EsepColors.textSecondary, height: 1.4),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Bank cards
          ..._banks.map((bank) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BankCard(
              bank: bank,
              syncInfo: _getSyncInfo(bank.key),
              dateFmt: _dateFmt,
              onConnect: () => _showBankFlow(bank),
            ),
          )),
        ],
      ),
    );
  }

  void _showBankFlow(_BankInfo bank) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) => _BankFlowSheet(
          bank: bank,
          scrollController: scrollCtrl,
          onLoadFile: () {
            Navigator.pop(ctx);
            _openImport();
          },
        ),
      ),
    );
  }

  void _openImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KaspiImportScreen()),
    );
    // Refresh sync status
    setState(() {});
  }
}

// ── Bank card widget ────────────────────────────────────────────────────────

class _BankCard extends StatelessWidget {
  const _BankCard({
    required this.bank,
    required this.syncInfo,
    required this.dateFmt,
    required this.onConnect,
  });

  final _BankInfo bank;
  final _BankSyncInfo? syncInfo;
  final DateFormat dateFmt;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final connected = syncInfo != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onConnect,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EsepColors.cardLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: connected
                  ? EsepColors.income.withValues(alpha: 0.4)
                  : EsepColors.divider,
              width: connected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(children: [
                // Bank icon
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: bank.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(bank.icon, color: bank.color, size: 24),
                ),
                const SizedBox(width: 14),

                // Name + subtitle
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(bank.name, style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: bank.color,
                      )),
                      if (connected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: EsepColors.income.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle, color: EsepColors.income, size: 12),
                            SizedBox(width: 4),
                            Text('Подключён', style: TextStyle(
                              fontSize: 11, color: EsepColors.income, fontWeight: FontWeight.w700,
                            )),
                          ]),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(bank.subtitle, style: const TextStyle(
                      fontSize: 12, color: EsepColors.textSecondary,
                    )),
                  ]),
                ),

                // Arrow
                Icon(
                  connected ? Iconsax.refresh : Iconsax.arrow_right_3,
                  color: connected ? EsepColors.income : EsepColors.textDisabled,
                  size: 20,
                ),
              ]),

              // Last sync info
              if (connected) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: EsepColors.income.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Iconsax.clock, size: 14, color: EsepColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Синхронизировано: ${dateFmt.format(syncInfo!.lastSync)}',
                      style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      '${syncInfo!.transactionCount} операций',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: EsepColors.textPrimary),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bank flow bottom sheet ──────────────────────────────────────────────────

class _BankFlowSheet extends StatelessWidget {
  const _BankFlowSheet({
    required this.bank,
    required this.scrollController,
    required this.onLoadFile,
  });

  final _BankInfo bank;
  final ScrollController scrollController;
  final VoidCallback onLoadFile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        // Handle
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: EsepColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Bank header
        Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: bank.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(bank.icon, color: bank.color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bank.name, style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: bank.color,
              )),
              const SizedBox(height: 2),
              const Text('Инструкция по подключению', style: TextStyle(
                fontSize: 13, color: EsepColors.textSecondary,
              )),
            ]),
          ),
        ]),
        const SizedBox(height: 28),

        // Steps
        ...bank.steps.asMap().entries.map((entry) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: bank.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${entry.key + 1}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: bank.color),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(entry.value, style: const TextStyle(
                  fontSize: 15, color: EsepColors.textPrimary, height: 1.4,
                )),
              ),
            ),
          ]),
        )),

        const SizedBox(height: 8),

        // Tip
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EsepColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EsepColors.warning.withValues(alpha: 0.2)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Iconsax.lamp_on, color: EsepColors.warning, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Esep автоматически распознает формат и категоризирует транзакции. '
                'Вы сможете проверить и изменить категории перед импортом.',
                style: TextStyle(fontSize: 13, color: EsepColors.textSecondary, height: 1.5),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // CTA button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Iconsax.document_upload, size: 20),
            label: const Text('Загрузить выписку', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              backgroundColor: bank.color,
            ),
            onPressed: onLoadFile,
          ),
        ),
        const SizedBox(height: 12),

        // Supported formats
        const Center(
          child: Text(
            'Поддерживаются .xlsx, .xls, .csv',
            style: TextStyle(fontSize: 12, color: EsepColors.textDisabled),
          ),
        ),
      ],
    );
  }
}
