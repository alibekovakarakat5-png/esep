import 'package:hive_flutter/hive_flutter.dart';

part 'client.g.dart';

@HiveType(typeId: 1)
class Client extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? bin; // БИН/ИИН

  @HiveField(3)
  String? phone;

  @HiveField(4)
  String? email;

  @HiveField(5)
  String? address;

  @HiveField(6)
  DateTime createdAt;

  Client({
    required this.id,
    required this.name,
    this.bin,
    this.phone,
    this.email,
    this.address,
    required this.createdAt,
  });
}
