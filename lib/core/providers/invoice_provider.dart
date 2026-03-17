import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/invoice.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';
import 'demo_provider.dart';

const _uuid = Uuid();

final invoiceLoadingProvider = StateProvider<bool>((ref) => true);

// Demo invoices
final _now = DateTime.now();
final _demoInvoices = [
  Invoice(
    id: 'demo-inv-1',
    number: 'СЧ-2026-001',
    clientName: 'ТОО АстанаТрейд',
    items: [
      const InvoiceItem(id: 'di-1', description: 'Консультация', quantity: 1, unitPrice: 540000),
    ],
    status: InvoiceStatus.paid,
    createdAt: _now.subtract(const Duration(days: 5)),
  ),
  Invoice(
    id: 'demo-inv-2',
    number: 'СЧ-2026-002',
    clientName: 'ИП Ахметова К.',
    items: [
      const InvoiceItem(id: 'di-2', description: 'Разработка сайта', quantity: 1, unitPrice: 285000),
    ],
    status: InvoiceStatus.sent,
    createdAt: _now.subtract(const Duration(days: 2)),
    dueDate: _now.add(const Duration(days: 5)),
  ),
  Invoice(
    id: 'demo-inv-3',
    number: 'СЧ-2026-003',
    clientName: 'ТОО Стройком',
    items: [
      const InvoiceItem(id: 'di-3', description: 'Поставка материалов', quantity: 10, unitPrice: 32000),
    ],
    status: InvoiceStatus.draft,
    createdAt: _now,
  ),
];

class InvoiceNotifier extends StateNotifier<List<Invoice>> {
  final Ref _ref;
  InvoiceNotifier(this._ref) : super([]) {
    _load();
  }

  Future<void> _load() async {
    if (_ref.read(isDemoProvider)) {
      state = _demoInvoices;
      _ref.read(invoiceLoadingProvider.notifier).state = false;
      return;
    }
    _ref.read(invoiceLoadingProvider.notifier).state = true;
    try {
      final data = await ApiClient.get('/invoices') as List<dynamic>;
      state = data
          .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      state = [];
    } finally {
      _ref.read(invoiceLoadingProvider.notifier).state = false;
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
  ref.watch(authProvider);
  return InvoiceNotifier(ref);
});

final unpaidInvoicesProvider = Provider<List<Invoice>>((ref) {
  return ref.watch(invoiceProvider).where((i) =>
      i.status == InvoiceStatus.sent || i.status == InvoiceStatus.overdue).toList();
});

final totalUnpaidProvider = Provider<double>((ref) {
  return ref.watch(unpaidInvoicesProvider).fold(0.0, (sum, i) => sum + i.totalAmount);
});
