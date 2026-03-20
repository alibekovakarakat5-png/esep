import 'package:hive_flutter/hive_flutter.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 3)
class ChatMessage extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String chatId; // clientId for accountant, accountantId for client

  @HiveField(2)
  String senderId;

  @HiveField(3)
  String senderName;

  @HiveField(4)
  String text;

  @HiveField(5)
  DateTime timestamp;

  @HiveField(6)
  bool isRead;

  @HiveField(7)
  String? attachmentPath; // local file path for document photos

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isRead = false,
    this.attachmentPath,
  });
}
