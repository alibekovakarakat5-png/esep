import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/client.dart';
import '../../../core/providers/client_provider.dart';
import '../../../core/providers/user_mode_provider.dart';
import '../../../core/services/excel_export_service.dart';
import '../../../shared/widgets/adaptive_sheet.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientProvider);
    final filtered = _query.isEmpty
        ? clients
        : clients
            .where((c) =>
                c.name.toLowerCase().contains(_query.toLowerCase()) ||
                (c.bin?.contains(_query) ?? false) ||
                (c.phone?.contains(_query) ?? false))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Поиск клиентов...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('Клиенты'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.document_download),
            tooltip: 'Экспорт в Excel',
            onPressed: () {
              final all = ref.read(clientProvider);
              if (all.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Нет клиентов для экспорта')),
                );
                return;
              }
              ExcelExportService.exportClients(all);
            },
          ),
          IconButton(
            icon: Icon(_searching ? Iconsax.close_circle : Iconsax.search_normal),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtrl.clear();
                _query = '';
              }
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        backgroundColor: EsepColors.primary,
        icon: const Icon(Iconsax.user_add, color: Colors.white),
        label: const Text('Добавить', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // Upsell banner for IP mode
          if (ref.watch(userModeProvider) != UserMode.accountant)
            _AccountantUpsellBanner(
              onSwitch: () {
                ref.read(userModeProvider.notifier).set(UserMode.accountant);
                context.go('/accountant');
              },
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        _query.isNotEmpty ? Iconsax.search_normal : Iconsax.people,
                        color: EsepColors.textDisabled,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _query.isNotEmpty ? 'Ничего не найдено' : 'Нет клиентов',
                        style: const TextStyle(
                            color: EsepColors.textSecondary, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      if (_query.isEmpty)
                        const Text('Нажмите "Добавить" для создания',
                            style: TextStyle(
                                color: EsepColors.textDisabled, fontSize: 13)),
                    ]),
                  )
                : isDesktop(context)
                  ? _buildDesktopTable(filtered)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _ClientTile(
                        client: filtered[i],
                        onDelete: () =>
                            ref.read(clientProvider.notifier).remove(filtered[i].id),
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(List<Client> clients) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: DataTable(
            columnSpacing: 24,
            headingRowColor: WidgetStateProperty.all(
              EsepColors.primary.withValues(alpha: 0.05),
            ),
            columns: const [
              DataColumn(label: Text('Название / ФИО', style: TextStyle(fontWeight: FontWeight.w600))),
              DataColumn(label: Text('БИН / ИИН', style: TextStyle(fontWeight: FontWeight.w600))),
              DataColumn(label: Text('Телефон', style: TextStyle(fontWeight: FontWeight.w600))),
              DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.w600))),
              DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.w600))),
            ],
            rows: clients.map((c) => DataRow(cells: [
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: EsepColors.primary.withValues(alpha: 0.15),
                  child: Text(c.name.substring(0, 1),
                      style: const TextStyle(color: EsepColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ])),
              DataCell(Text(c.bin ?? '—', style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary))),
              DataCell(Text(c.phone ?? '—', style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary))),
              DataCell(Text(c.email ?? '—', style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary))),
              DataCell(IconButton(
                icon: const Icon(Iconsax.trash, size: 18, color: EsepColors.expense),
                tooltip: 'Удалить',
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Удалить?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Удалить', style: TextStyle(color: EsepColors.expense)),
                        ),
                      ],
                    ),
                  ) ?? false;
                  if (ok) ref.read(clientProvider.notifier).remove(c.id);
                },
              )),
            ])).toList(),
          ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final binCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showAdaptiveSheet(
      context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 24, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Новый клиент',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Название / ФИО', prefixIcon: Icon(Iconsax.user)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: binCtrl,
            decoration: const InputDecoration(
                labelText: 'БИН / ИИН', prefixIcon: Icon(Iconsax.document)),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(
                labelText: 'Телефон', prefixIcon: Icon(Iconsax.call)),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            decoration: const InputDecoration(
                labelText: 'Email', prefixIcon: Icon(Iconsax.sms)),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              ref.read(clientProvider.notifier).add(
                    name: nameCtrl.text.trim(),
                    bin: binCtrl.text.trim().isEmpty
                        ? null
                        : binCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty
                        ? null
                        : phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim().isEmpty
                        ? null
                        : emailCtrl.text.trim(),
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ]),
      ),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client, required this.onDelete});
  final Client client;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Dismissible(
        key: Key(client.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: EsepColors.expense.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Iconsax.trash, color: EsepColors.expense),
        ),
        confirmDismiss: (_) async {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Удалить?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Удалить', style: TextStyle(color: EsepColors.expense)),
                ),
              ],
            ),
          ) ?? false;
        },
        onDismissed: (_) => onDelete(),
        child: Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: CircleAvatar(
              backgroundColor: EsepColors.primary.withValues(alpha: 0.15),
              child: Text(
                client.name.substring(0, 1),
                style: const TextStyle(
                    color: EsepColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(client.name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text(
              [
                if (client.bin != null) 'БИН: ${client.bin}',
                if (client.phone != null) client.phone,
              ].join(' · '),
              style: const TextStyle(
                  fontSize: 12, color: EsepColors.textSecondary),
            ),
          ),
        ),
      );
}

class _AccountantUpsellBanner extends StatelessWidget {
  const _AccountantUpsellBanner({required this.onSwitch});
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            EsepColors.primary.withValues(alpha: 0.08),
            EsepColors.info.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: EsepColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: EsepColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Iconsax.people, color: EsepColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ведёте учёт нескольких ИП?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: EsepColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Режим Бухгалтера — дедлайны, документы и отчёты по каждому клиенту',
                  style: TextStyle(
                    fontSize: 12,
                    color: EsepColors.textSecondary.withValues(alpha: 0.8),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onSwitch,
            style: TextButton.styleFrom(
              backgroundColor: EsepColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Перейти', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
