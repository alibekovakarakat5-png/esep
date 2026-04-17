import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ── State ────────────────────────────────────────────────────────────────────

class _Message {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;

  const _Message({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, String> toApi() => {'role': role, 'content': content};
}

class _ChatState {
  final List<_Message> messages;
  final bool isLoading;
  final String? error;

  const _ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  _ChatState copyWith({
    List<_Message>? messages,
    bool? isLoading,
    String? error,
  }) =>
      _ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class _ChatNotifier extends StateNotifier<_ChatState> {
  _ChatNotifier() : super(const _ChatState());

  Future<void> send(String text) async {
    final userMsg = _Message(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      error: null,
    );

    try {
      final apiMessages = state.messages.map((m) => m.toApi()).toList();
      final data = await ApiClient.post('/ai-chat', {'messages': apiMessages});

      final reply = _Message(
        role: 'assistant',
        content: data['reply'] as String,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, reply],
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Нет соединения с сервером',
      );
    }
  }

  void clearChat() => state = const _ChatState();
}

final _chatProvider =
    StateNotifierProvider<_ChatNotifier, _ChatState>((_) => _ChatNotifier());

// ── Quick prompts ────────────────────────────────────────────────────────────

const _quickPrompts = [
  '💰 Сколько налогов на упрощёнке при доходе 5 млн за полугодие?',
  '📊 Сравни все режимы для ИП с доходом 1 млн/мес',
  '📅 Когда сдавать 910 форму?',
  '🧮 Сколько соцплатежей в месяц за себя?',
  '🏢 Когда нужно вставать на учёт по НДС?',
  '❓ Чем отличается ЕСП от самозанятого?',
];

// ── Screen ───────────────────────────────────────────────────────────────────

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(_chatProvider.notifier).send(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(_chatProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<_ChatState>(_chatProvider, (prev, next) {
      if (next.messages.length > (prev?.messages.length ?? 0)) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.message_question, size: 22),
            SizedBox(width: 8),
            Text('AI Бухгалтер'),
          ],
        ),
        actions: [
          if (chat.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Iconsax.trash, size: 20),
              tooltip: 'Очистить чат',
              onPressed: () => ref.read(_chatProvider.notifier).clearChat(),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Messages ────────────────────────────────────────────────────
          Expanded(
            child: chat.messages.isEmpty
                ? _EmptyState(onTap: (prompt) {
                    _controller.text = prompt;
                    _send();
                  })
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: chat.messages.length +
                        (chat.isLoading ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == chat.messages.length && chat.isLoading) {
                        return const _TypingIndicator();
                      }
                      return _MessageBubble(
                        message: chat.messages[i],
                        isDark: isDark,
                      );
                    },
                  ),
          ),

          // ── Error ───────────────────────────────────────────────────────
          if (chat.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: EsepColors.expense.withValues(alpha: 0.1),
              child: Text(
                chat.error!,
                style: const TextStyle(color: EsepColors.expense, fontSize: 13),
              ),
            ),

          // ── Input ───────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: isDark ? EsepColors.surfaceDark : Colors.white,
              border: const Border(
                top: BorderSide(color: EsepColors.divider, width: 1),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Задайте вопрос по налогам...',
                        hintStyle: const TextStyle(
                          color: EsepColors.textDisabled,
                          fontSize: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? EsepColors.cardDark
                            : EsepColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: chat.isLoading
                          ? EsepColors.textDisabled
                          : EsepColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Iconsax.send_1, color: Colors.white, size: 20),
                      onPressed: chat.isLoading ? null : _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state with quick prompts ───────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: EsepColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.message_question,
              size: 36,
              color: EsepColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'AI Бухгалтер',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Задайте любой вопрос по налогам,\nрежимам, соцплатежам и дедлайнам',
            textAlign: TextAlign.center,
            style: TextStyle(color: EsepColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _quickPrompts.map((p) {
              return ActionChip(
                label: Text(p, style: const TextStyle(fontSize: 13)),
                onPressed: () => onTap(p),
                backgroundColor: EsepColors.surface,
                side: const BorderSide(color: EsepColors.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isDark});
  final _Message message;
  final bool isDark;

  bool get isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: EsepColors.primary,
              child: const Text(
                'e',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? EsepColors.primary
                    : (isDark ? EsepColors.cardDark : EsepColors.surface),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: isUser
                          ? Colors.white
                          : (isDark ? Colors.white : EsepColors.textPrimary),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (!isUser) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: message.content),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Скопировано'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Icon(
                            Iconsax.copy,
                            size: 14,
                            color: EsepColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ── Typing indicator ─────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: EsepColors.primary,
            child: const Text(
              'e',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: EsepColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EsepColors.primary,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Считаю...',
                  style: TextStyle(
                    color: EsepColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
