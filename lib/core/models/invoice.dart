enum InvoiceStatus { draft, sent, paid, overdue }

/// Каталог единиц измерения по классификатору ОКЕИ
/// (используется в ЭСФ — поле UNIT_CODE)
class InvoiceUnit {
  final String code; // ОКЕИ
  final String name; // короткое имя

  const InvoiceUnit(this.code, this.name);

  static const piece    = InvoiceUnit('796', 'штука');
  static const service  = InvoiceUnit('931', 'услуга');
  static const hour     = InvoiceUnit('356', 'час');
  static const day      = InvoiceUnit('359', 'день');
  static const month    = InvoiceUnit('362', 'месяц');
  static const kg       = InvoiceUnit('166', 'кг');
  static const ton      = InvoiceUnit('168', 'тонна');
  static const liter    = InvoiceUnit('112', 'литр');
  static const m2       = InvoiceUnit('055', 'м²');
  static const m3       = InvoiceUnit('113', 'м³');
  static const km       = InvoiceUnit('008', 'км');
  static const set      = InvoiceUnit('704', 'комплект');
  static const pack     = InvoiceUnit('736', 'упаковка');

  static const all = <InvoiceUnit>[
    piece, service, hour, day, month,
    kg, ton, liter, m2, m3, km, set, pack,
  ];

  static InvoiceUnit byCode(String code) =>
      all.firstWhere((u) => u.code == code, orElse: () => piece);
}

class InvoiceItem {
  final String id;
  final String description;
  final double quantity;
  final double unitPrice;
  /// ОКЕИ-код единицы измерения. По умолчанию '796' (штука).
  final String unitCode;
  /// Человекочитаемое имя единицы (для PDF/XML).
  final String unitName;

  double get total => quantity * unitPrice;

  const InvoiceItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.unitCode = '796',
    this.unitName = 'штука',
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        id: j['id'] as String,
        description: j['description'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unitPrice: (j['unit_price'] as num).toDouble(),
        unitCode: (j['unit_code'] as String?) ?? '796',
        unitName: (j['unit_name'] as String?) ?? 'штука',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'unit_code': unitCode,
        'unit_name': unitName,
      };

  InvoiceItem copyWith({
    String? id,
    String? description,
    double? quantity,
    double? unitPrice,
    String? unitCode,
    String? unitName,
  }) =>
      InvoiceItem(
        id: id ?? this.id,
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        unitCode: unitCode ?? this.unitCode,
        unitName: unitName ?? this.unitName,
      );
}

class Invoice {
  final String id;
  final String number; // СЧ-2026-001
  final String? clientId;
  final String clientName;
  /// ИИН/БИН покупателя. Обязателен для ЭСФ при отгрузке юрлицам/ИП.
  /// Может быть null для розничных продаж физлицам.
  final String? buyerIin;
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
    this.buyerIin,
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
      buyerIin: j['buyer_iin'] as String?,
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
        if (buyerIin != null && buyerIin!.isNotEmpty) 'buyer_iin': buyerIin,
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
    String? buyerIin,
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
        buyerIin: buyerIin ?? this.buyerIin,
        items: items ?? this.items,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        dueDate: dueDate ?? this.dueDate,
        notes: notes ?? this.notes,
      );
}
