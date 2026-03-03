import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/invoice.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

const _uuid = Uuid();

class InvoiceNotifier extends StateNotifier<List<Invoice>> {
  InvoiceNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.get('/invoices') as List<dynamic>;
      state = data
          .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      state = [];
    }
  }

  String _nextNumber() {
    final year = DateTime.now().year;
    final count = state.where((i) => i.createdAt.year == year).length + 1;
    return 'СЧ-$year-${count.toString().padLeft(3, '0')}';
  }

  Future<void> add({
    String? clientId,
    required String clientName,
    required List<InvoiceItem> items,
    DateTime? dueDate,
    String? notes,
  }) async {
    final id = _uuid.v4();
    final invoice = Invoice(
      id: id,
      number: _nextNumber(),
      clientId: clientId,
      clientName: clientName,
      items: items
          .map((item) => item.id.isEmpty
              ? InvoiceItem(
                  id: _uuid.v4(),
                  description: item.description,
                  quantity: item.quantity,
                  unitPrice: item.unitPrice,
                )
              : item)
          .toList(),
      status: InvoiceStatus.draft,
      createdAt: DateTime.now(),
      dueDate: dueDate,
      notes: notes,
    );
    await ApiClient.post('/invoices', invoice.toJson());
    await _load();
  }

  Future<void> updateStatus(String id, InvoiceStatus status) async {
    await ApiClient.put('/invoices/$id', {'status': status.name});
    await _load();
  }

  Future<void> remove(String id) async {
    await ApiClient.delete('/invoices/$id');
    await _load();
  }
}

final invoiceProvider =
    StateNotifierProvider<InvoiceNotifier, List<Invoice>>((ref) {
  // Reload when auth changes
  ref.watch(authProvider);
  return InvoiceNotifier();
});

// Derived

final unpaidInvoicesProvider = Provider<List<Invoice>>((ref) {
  return ref.watch(invoiceProvider).where((i) =>
      i.status == InvoiceStatus.sent || i.status == InvoiceStatus.overdue).toList();
});

final totalUnpaidProvider = Provider<double>((ref) {
  return ref.watch(unpaidInvoicesProvider).fold(0.0, (sum, i) => sum + i.totalAmount);
});
