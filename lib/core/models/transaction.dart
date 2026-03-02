import 'package:hive_flutter/hive_flutter.dart';

part 'transaction.g.dart';

@HiveType(typeId: 0)
class Transaction extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  double amount;

  @HiveField(3)
  bool isIncome;

  @HiveField(4)
  DateTime date;

  @HiveField(5)
  String? clientName;

  @HiveField(6)
  String? source; // kaspi, наличные, перевод, карта

  @HiveField(7)
  String? note;

  @HiveField(8)
  String? category;

  Transaction({
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
}
