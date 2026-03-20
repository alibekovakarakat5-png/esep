import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/company_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId, required this.chatName});
  final String chatId;
  final String chatName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Mark messages as read when entering chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final company = ref.read(companyProvider);
      ref.read(chatProvider.notifier).markAsRead(widget.chatId, company.iin);
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    final company = ref.read(companyProvider);
    ref.read(chatProvider.notifier).send(
          chatId: widget.chatId,
          senderId: company.iin,
          senderName: company.name.isNotEmpty ? company.name : 'Бухгалтер',
          text: text,
        );
    _msgCtrl.clear();
    _scrollToBottom();
  }

  Future<void> _attachPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1280);
    if (picked == null) return;

    final company = ref.read(companyProvider);
    ref.read(chatProvider.notifier).send(
          chatId: widget.chatId,
          senderId: company.iin,
          senderName: company.name.isNotEmpty ? company.name : 'Бухгалтер',
          text: 'Документ',
          attachmentPath: picked.path,
        );
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allMessages = ref.watch(chatProvider);
    final messages = allMessages
        .where((m) => m.chatId == widget.chatId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final company = ref.watch(companyProvider);
    final myId = company.iin;
    final dateFmt = DateFormat('HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatName, style: const TextStyle(fontSize: 16)),
            Text(
              '${messages.length} сообщений',
              style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Iconsax.message, size: 48, color: EsepColors.textDisabled),
                      SizedBox(height: 12),
                      Text('Нет сообщений', style: TextStyle(color: EsepColors.textSecondary)),
                      SizedBox(height: 4),
                      Text('Напишите первое сообщение',
                          style: TextStyle(fontSize: 12, color: EsepColors.textDisabled)),
                    ]),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final msg = messages[i];
                      final isMe = msg.senderId == myId;
                      return _MessageBubble(
                        message: msg,
                        isMe: isMe,
                        timeFmt: dateFmt,
                      );
                    },
                  ),
          ),

          // Quick actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _QuickAction(label: 'Пришлите выписку', onTap: () {
                  _msgCtrl.text = 'Пришлите, пожалуйста, банковскую выписку за текущий месяц';
                }),
                _QuickAction(label: 'Нужен акт', onTap: () {
                  _msgCtrl.text = 'Необходим акт выполненных работ. Можете прислать?';
                }),
                _QuickAction(label: 'Дедлайн скоро', onTap: () {
                  _msgCtrl.text = 'Приближается срок сдачи отчётности. Нужны документы до конца недели.';
                }),
              ]),
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(children: [
                IconButton(
                  icon: const Icon(Iconsax.attach_circle, color: EsepColors.primary),
                  onPressed: _attachPhoto,
                  tooltip: 'Прикрепить фото',
                ),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: 'Сообщение...',
                      filled: true,
                      fillColor: EsepColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Iconsax.send_1, color: EsepColors.primary),
                  onPressed: _send,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe, required this.timeFmt});
  final ChatMessage message;
  final bool isMe;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? EsepColors.primary : EsepColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(message.senderName,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: EsepColors.primary)),
            if (message.attachmentPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(message.attachmentPath!),
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Iconsax.image, size: 40, color: EsepColors.textDisabled),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                color: isMe ? Colors.white : EsepColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                timeFmt.format(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : EsepColors.textDisabled,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  message.isRead ? Iconsax.tick_circle : Iconsax.tick_square,
                  size: 12,
                  color: message.isRead ? Colors.white : Colors.white54,
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: onTap,
        backgroundColor: EsepColors.primary.withValues(alpha: 0.08),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}
