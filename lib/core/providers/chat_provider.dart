import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';

const _uuid = Uuid();

/// Chat feature is disabled for now.
/// When enabled, replace in-memory storage with Hive or Firebase.
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier() : super([]);

  List<ChatMessage> messagesFor(String chatId) =>
      state.where((m) => m.chatId == chatId).toList();

  int unreadCount(String chatId, String currentUserId) =>
      state.where((m) =>
          m.chatId == chatId &&
          m.senderId != currentUserId &&
          !m.isRead).length;

  int totalUnread(String currentUserId) =>
      state.where((m) => m.senderId != currentUserId && !m.isRead).length;

  List<ChatSummary> getChatSummaries(String currentUserId) {
    final chatIds = state.map((m) => m.chatId).toSet();
    final summaries = <ChatSummary>[];
    for (final chatId in chatIds) {
      final messages = messagesFor(chatId);
      if (messages.isEmpty) continue;
      final last = messages.last;
      summaries.add(ChatSummary(
        chatId: chatId,
        lastMessage: last,
        unreadCount: unreadCount(chatId, currentUserId),
      ));
    }
    summaries.sort((a, b) =>
        b.lastMessage.timestamp.compareTo(a.lastMessage.timestamp));
    return summaries;
  }

  Future<void> send({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
    String? attachmentPath,
  }) async {
    final msg = ChatMessage(
      id: _uuid.v4(),
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      timestamp: DateTime.now(),
      attachmentPath: attachmentPath,
    );
    state = [...state, msg];
  }

  Future<void> markAsRead(String chatId, String currentUserId) async {
    state = [
      for (final m in state)
        if (m.chatId == chatId && m.senderId != currentUserId && !m.isRead)
          (m..isRead = true)
        else
          m,
    ];
  }

  Future<void> deleteMessage(String messageId) async {
    state = state.where((m) => m.id != messageId).toList();
  }
}

class ChatSummary {
  final String chatId;
  final ChatMessage lastMessage;
  final int unreadCount;

  const ChatSummary({
    required this.chatId,
    required this.lastMessage,
    required this.unreadCount,
  });
}

final chatProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) {
  return ChatNotifier();
});
