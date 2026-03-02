import 'package:hive_flutter/hive_flutter.dart';

part 'invoice.g.dart';

@HiveType(typeId: 2)
enum InvoiceStatus {
  @HiveField(0)
  draft,
  @HiveField(1)
  sent,
  @HiveField(2)
  paid,
  @HiveField(3)
  overdue,
}

@HiveType(typeId: 3)
class InvoiceItem {
  @HiveField(0)
  String description;

  @HiveField(1)
  int quantity;

  @HiveField(2)
  double unitPrice;

  double get total => quantity * unitPrice;

  InvoiceItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });
}

@HiveType(typeId: 4)
class Invoice extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String number; // СЧ-2026-001

  @HiveField(2)
  String clientId;

  @HiveField(3)
  String clientName;

  @HiveField(4)
  List<InvoiceItem> items;

  @HiveField(5)
  InvoiceStatus status;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  DateTime? dueDate;

  @HiveField(8)
  DateTime? paidAt;

  @HiveField(9)
  String? note;

  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);

  Invoice({
    required this.id,
    required this.number,
    required this.clientId,
    required this.clientName,
    required this.items,
    required this.status,
    required this.createdAt,
    this.dueDate,
    this.paidAt,
    this.note,
  });
}
