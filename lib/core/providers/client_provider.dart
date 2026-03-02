import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/client.dart';
import '../services/hive_service.dart';

const _uuid = Uuid();

class ClientNotifier extends StateNotifier<List<Client>> {
  ClientNotifier() : super([]) {
    _load();
  }

  void _load() {
    state = HiveService.clients.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> add({
    required String name,
    String? bin,
    String? phone,
    String? email,
    String? address,
  }) async {
    final client = Client(
      id: _uuid.v4(),
      name: name,
      bin: bin,
      phone: phone,
      email: email,
      address: address,
      createdAt: DateTime.now(),
    );
    await HiveService.clients.put(client.id, client);
    _load();
  }

  Future<void> remove(String id) async {
    await HiveService.clients.delete(id);
    _load();
  }

  Future<void> update(Client client) async {
    await HiveService.clients.put(client.id, client);
    _load();
  }
}

final clientProvider =
    StateNotifierProvider<ClientNotifier, List<Client>>((ref) {
  return ClientNotifier();
});
