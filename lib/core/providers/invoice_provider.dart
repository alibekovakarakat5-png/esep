import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/invoice.dart';
import '../services/hive_service.dart';

const _uuid = Uuid();

class InvoiceNotifier extends StateNotifier<List<Invoice>> {
  InvoiceNotifier() : super([]) {
    _load();
  }

  void _load() {
    state = HiveService.invoices.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  String _nextNumber() {
    final year = DateTime.now().year;
    final count = state.where((i) => i.createdAt.year == year).length + 1;
    return 'СЧ-$year-${count.toString().padLeft(3, '0')}';
  }

  Future<void> add({
    required String clientId,
    required String clientName,
    required List<InvoiceItem> items,
    DateTime? dueDate,
    String? note,
  }) async {
    final invoice = Invoice(
      id: _uuid.v4(),
      number: _nextNumber(),
      clientId: clientId,
      clientName: clientName,
      items: items,
      status: InvoiceStatus.draft,
      createdAt: DateTime.now(),
      dueDate: dueDate,
      note: note,
    );
    await HiveService.invoices.put(invoice.id, invoice);
    _load();
  }

  Future<void> updateStatus(String id, InvoiceStatus status) async {
    final invoice = HiveService.invoices.get(id);
    if (invoice != null) {
      invoice.status = status;
      if (status == InvoiceStatus.paid) invoice.paidAt = DateTime.now();
      await invoice.save();
      _load();
    }
  }

  Future<void> remove(String id) async {
    await HiveService.invoices.delete(id);
    _load();
  }
}

final invoiceProvider =
    StateNotifierProvider<InvoiceNotifier, List<Invoice>>((ref) {
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
