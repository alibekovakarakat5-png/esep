import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/client.dart';
import '../../../core/providers/client_provider.dart';

class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Клиенты'),
        actions: [
          IconButton(icon: const Icon(Iconsax.search_normal), onPressed: () {}),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        backgroundColor: EsepColors.primary,
        icon: const Icon(Iconsax.user_add, color: Colors.white),
        label: const Text('Добавить', style: TextStyle(color: Colors.white)),
      ),
      body: clients.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Iconsax.people, color: EsepColors.textDisabled, size: 48),
                SizedBox(height: 12),
                Text('Нет клиентов', style: TextStyle(color: EsepColors.textSecondary, fontSize: 16)),
                SizedBox(height: 4),
                Text('Нажмите "Добавить" для создания',
                    style: TextStyle(color: EsepColors.textDisabled, fontSize: 13)),
              ]),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: clients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ClientTile(
                client: clients[i],
                onDelete: () => ref.read(clientProvider.notifier).remove(clients[i].id),
              ),
            ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final binCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Новый клиент', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Название / ФИО', prefixIcon: Icon(Iconsax.user)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: binCtrl,
            decoration: const InputDecoration(labelText: 'БИН / ИИН', prefixIcon: Icon(Iconsax.document)),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(labelText: 'Телефон', prefixIcon: Icon(Iconsax.call)),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Iconsax.sms)),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              ref.read(clientProvider.notifier).add(
                    name: nameCtrl.text.trim(),
                    bin: binCtrl.text.trim().isEmpty ? null : binCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
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
        onDismissed: (_) => onDelete(),
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: CircleAvatar(
              backgroundColor: EsepColors.primary.withValues(alpha: 0.15),
              child: Text(
                client.name.substring(0, 1),
                style: const TextStyle(color: EsepColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(client.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text(
              [
                if (client.bin != null) 'БИН: ${client.bin}',
                if (client.phone != null) client.phone,
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
            ),
          ),
        ),
      );
}
