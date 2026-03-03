enum InvoiceStatus { draft, sent, paid, overdue }

class InvoiceItem {
  final String id;
  final String description;
  final double quantity;
  final double unitPrice;

  double get total => quantity * unitPrice;

  const InvoiceItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        id: j['id'] as String,
        description: j['description'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unitPrice: (j['unit_price'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}

class Invoice {
  final String id;
  final String number; // СЧ-2026-001
  final String? clientId;
  final String clientName;
  final List<InvoiceItem> items;
  final InvoiceStatus status;
  final DateTime createdAt;
  final DateTime? dueDate;
  final String? notes;

  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);

  const Invoice({
    required this.id,
    required this.number,
    this.clientId,
    required this.clientName,
    required this.items,
    required this.status,
    required this.createdAt,
    this.dueDate,
    this.notes,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final statusStr = j['status'] as String? ?? 'draft';
    final status = InvoiceStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => InvoiceStatus.draft,
    );
    final rawItems = j['items'] as List<dynamic>? ?? [];
    return Invoice(
      id: j['id'] as String,
      number: j['number'] as String,
      clientId: j['client_id'] as String?,
      clientName: j['client_name'] as String,
      items: rawItems.map((i) => InvoiceItem.fromJson(i as Map<String, dynamic>)).toList(),
      status: status,
      createdAt: DateTime.parse(j['created_at'] as String),
      dueDate: j['due_date'] != null ? DateTime.parse(j['due_date'] as String) : null,
      notes: j['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        if (clientId != null) 'client_id': clientId,
        'client_name': clientName,
        'items': items.map((i) => i.toJson()).toList(),
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        if (dueDate != null) 'due_date': dueDate!.toIso8601String().split('T').first,
        if (notes != null) 'notes': notes,
      };

  Invoice copyWith({
    String? id,
    String? number,
    String? clientId,
    String? clientName,
    List<InvoiceItem>? items,
    InvoiceStatus? status,
    DateTime? createdAt,
    DateTime? dueDate,
    String? notes,
  }) =>
      Invoice(
        id: id ?? this.id,
        number: number ?? this.number,
        clientId: clientId ?? this.clientId,
        clientName: clientName ?? this.clientName,
        items: items ?? this.items,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        dueDate: dueDate ?? this.dueDate,
        notes: notes ?? this.notes,
      );
}
