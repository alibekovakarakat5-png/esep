import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';

class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  static const _mock = [
    _ClientMock('Ромашка ТОО', '123456789012', 3, 225000),
    _ClientMock('ИП Сейткали А.', '870512345678', 5, 0),
    _ClientMock('Алтын Групп ТОО', '234567890123', 1, 320000),
    _ClientMock('ТехСервис ИП', '560712345678', 2, 0),
  ];

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Клиенты'),
        actions: [
          IconButton(icon: const Icon(Iconsax.search_normal), onPressed: () {}),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: EsepColors.primary,
        icon: const Icon(Iconsax.user_add, color: Colors.white),
        label: const Text('Добавить', style: TextStyle(color: Colors.white)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _mock.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _ClientTile(client: _mock[i], fmt: fmt),
      ),
    );
  }
}

class _ClientMock {
  const _ClientMock(this.name, this.bin, this.invoiceCount, this.debt);
  final String name, bin;
  final int invoiceCount;
  final double debt;
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client, required this.fmt});
  final _ClientMock client;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) => Card(
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
          subtitle: Text('БИН/ИИН: ${client.bin}', style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${client.invoiceCount} счёт(а)', style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              if (client.debt > 0) ...[
                const SizedBox(height: 4),
                Text('${fmt.format(client.debt)} ₸', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: EsepColors.expense)),
              ],
            ],
          ),
          onTap: () {},
        ),
      );
}
