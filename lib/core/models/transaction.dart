class Transaction {
  final String id;
  final String title;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final String? clientName;
  final String? source; // kaspi, наличные, перевод, карта
  final String? note;
  final String? category;

  const Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.date,
    this.clientName,
    this.source,
    this.note,
    this.category,
  });

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String,
        title: j['title'] as String,
        amount: (j['amount'] as num).toDouble(),
        isIncome: j['is_income'] as bool,
        date: DateTime.parse(j['date'] as String),
        clientName: j['client_name'] as String?,
        source: j['source'] as String?,
        note: j['note'] as String?,
        category: j['category'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'is_income': isIncome,
        'date': date.toIso8601String().split('T').first,
        if (clientName != null) 'client_name': clientName,
        if (source != null) 'source': source,
        if (note != null) 'note': note,
        if (category != null) 'category': category,
      };

  Transaction copyWith({
    String? id,
    String? title,
    double? amount,
    bool? isIncome,
    DateTime? date,
    String? clientName,
    String? source,
    String? note,
    String? category,
  }) =>
      Transaction(
        id: id ?? this.id,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        isIncome: isIncome ?? this.isIncome,
        date: date ?? this.date,
        clientName: clientName ?? this.clientName,
        source: source ?? this.source,
        note: note ?? this.note,
        category: category ?? this.category,
      );
}
