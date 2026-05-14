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

  /// Код единицы измерения справочника ИС ЭСФ (тег `unitNomenclature`).
  /// Отдельно от ОКЕИ `unitCode` — у ИС ЭСФ собственный справочник,
  /// официальных кодов для услуг/работ КГД не публикует. Заполняется
  /// бухгалтером из своей учётной системы (1С). null → тег не выводится.
  final String? esfUnitCode;
  /// ID товара/услуги из каталога ТРУ (тег `catalogTruId`). По умолчанию '1'.
  final String catalogTruId;
  /// Код происхождения ТРУ (тег `truOriginCode`). '5' — работы/услуги.
  final String truOriginCode;

  double get total => quantity * unitPrice;

  const InvoiceItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.unitCode = '796',
    this.unitName = 'штука',
    this.esfUnitCode,
    this.catalogTruId = '1',
    this.truOriginCode = '5',
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        id: j['id'] as String,
        description: j['description'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unitPrice: (j['unit_price'] as num).toDouble(),
        unitCode: (j['unit_code'] as String?) ?? '796',
        unitName: (j['unit_name'] as String?) ?? 'штука',
        esfUnitCode: j['esf_unit_code'] as String?,
        catalogTruId: (j['catalog_tru_id'] as String?) ?? '1',
        truOriginCode: (j['tru_origin_code'] as String?) ?? '5',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'unit_code': unitCode,
        'unit_name': unitName,
        if (esfUnitCode != null && esfUnitCode!.isNotEmpty)
          'esf_unit_code': esfUnitCode,
        'catalog_tru_id': catalogTruId,
        'tru_origin_code': truOriginCode,
      };

  InvoiceItem copyWith({
    String? id,
    String? description,
    double? quantity,
    double? unitPrice,
    String? unitCode,
    String? unitName,
    String? esfUnitCode,
    String? catalogTruId,
    String? truOriginCode,
  }) =>
      InvoiceItem(
        id: id ?? this.id,
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        unitCode: unitCode ?? this.unitCode,
        unitName: unitName ?? this.unitName,
        esfUnitCode: esfUnitCode ?? this.esfUnitCode,
        catalogTruId: catalogTruId ?? this.catalogTruId,
        truOriginCode: truOriginCode ?? this.truOriginCode,
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

  // ── Реквизиты для ЭСФ ──────────────────────────────────────────────
  /// Дата оборота по реализации. null → используется [createdAt].
  final DateTime? turnoverDate;
  /// Номер договора-основания (тег `deliveryTerm/contractNum`).
  final String? contractNum;
  /// Дата договора-основания (тег `deliveryTerm/contractDate`).
  final DateTime? contractDate;
  /// Номер документа-основания: акт/накладная (тег `deliveryDocNum`).
  final String? deliveryDocNum;
  /// Дата документа-основания (тег `deliveryDocDate`).
  final DateTime? deliveryDocDate;
  /// Грузоотправитель совпадает с поставщиком. По умолчанию true.
  final bool consignorSameAsSeller;
  final String? consignorName;
  final String? consignorAddress;
  final String? consignorTin;
  /// Грузополучатель совпадает с покупателем. По умолчанию true.
  final bool consigneeSameAsCustomer;
  final String? consigneeName;
  final String? consigneeAddress;
  final String? consigneeTin;

  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);

  /// true → договор-основание заполнен (тег `hasContract`).
  bool get hasContract => contractNum != null && contractNum!.isNotEmpty;

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
    this.turnoverDate,
    this.contractNum,
    this.contractDate,
    this.deliveryDocNum,
    this.deliveryDocDate,
    this.consignorSameAsSeller = true,
    this.consignorName,
    this.consignorAddress,
    this.consignorTin,
    this.consigneeSameAsCustomer = true,
    this.consigneeName,
    this.consigneeAddress,
    this.consigneeTin,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final statusStr = j['status'] as String? ?? 'draft';
    final status = InvoiceStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => InvoiceStatus.draft,
    );
    final rawItems = j['items'] as List<dynamic>? ?? [];
    DateTime? parseDate(String key) =>
        j[key] != null ? DateTime.parse(j[key] as String) : null;
    return Invoice(
      id: j['id'] as String,
      number: j['number'] as String,
      clientId: j['client_id'] as String?,
      clientName: j['client_name'] as String,
      buyerIin: j['buyer_iin'] as String?,
      items: rawItems.map((i) => InvoiceItem.fromJson(i as Map<String, dynamic>)).toList(),
      status: status,
      createdAt: DateTime.parse(j['created_at'] as String),
      dueDate: parseDate('due_date'),
      notes: j['notes'] as String?,
      turnoverDate: parseDate('turnover_date'),
      contractNum: j['contract_num'] as String?,
      contractDate: parseDate('contract_date'),
      deliveryDocNum: j['delivery_doc_num'] as String?,
      deliveryDocDate: parseDate('delivery_doc_date'),
      consignorSameAsSeller: (j['consignor_same_as_seller'] as bool?) ?? true,
      consignorName: j['consignor_name'] as String?,
      consignorAddress: j['consignor_address'] as String?,
      consignorTin: j['consignor_tin'] as String?,
      consigneeSameAsCustomer: (j['consignee_same_as_customer'] as bool?) ?? true,
      consigneeName: j['consignee_name'] as String?,
      consigneeAddress: j['consignee_address'] as String?,
      consigneeTin: j['consignee_tin'] as String?,
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
        if (turnoverDate != null)
          'turnover_date': turnoverDate!.toIso8601String().split('T').first,
        if (contractNum != null) 'contract_num': contractNum,
        if (contractDate != null)
          'contract_date': contractDate!.toIso8601String().split('T').first,
        if (deliveryDocNum != null) 'delivery_doc_num': deliveryDocNum,
        if (deliveryDocDate != null)
          'delivery_doc_date': deliveryDocDate!.toIso8601String().split('T').first,
        'consignor_same_as_seller': consignorSameAsSeller,
        if (consignorName != null) 'consignor_name': consignorName,
        if (consignorAddress != null) 'consignor_address': consignorAddress,
        if (consignorTin != null) 'consignor_tin': consignorTin,
        'consignee_same_as_customer': consigneeSameAsCustomer,
        if (consigneeName != null) 'consignee_name': consigneeName,
        if (consigneeAddress != null) 'consignee_address': consigneeAddress,
        if (consigneeTin != null) 'consignee_tin': consigneeTin,
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
    DateTime? turnoverDate,
    String? contractNum,
    DateTime? contractDate,
    String? deliveryDocNum,
    DateTime? deliveryDocDate,
    bool? consignorSameAsSeller,
    String? consignorName,
    String? consignorAddress,
    String? consignorTin,
    bool? consigneeSameAsCustomer,
    String? consigneeName,
    String? consigneeAddress,
    String? consigneeTin,
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
        turnoverDate: turnoverDate ?? this.turnoverDate,
        contractNum: contractNum ?? this.contractNum,
        contractDate: contractDate ?? this.contractDate,
        deliveryDocNum: deliveryDocNum ?? this.deliveryDocNum,
        deliveryDocDate: deliveryDocDate ?? this.deliveryDocDate,
        consignorSameAsSeller:
            consignorSameAsSeller ?? this.consignorSameAsSeller,
        consignorName: consignorName ?? this.consignorName,
        consignorAddress: consignorAddress ?? this.consignorAddress,
        consignorTin: consignorTin ?? this.consignorTin,
        consigneeSameAsCustomer:
            consigneeSameAsCustomer ?? this.consigneeSameAsCustomer,
        consigneeName: consigneeName ?? this.consigneeName,
        consigneeAddress: consigneeAddress ?? this.consigneeAddress,
        consigneeTin: consigneeTin ?? this.consigneeTin,
      );
}
