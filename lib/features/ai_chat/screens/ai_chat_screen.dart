import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/user_mode_provider.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class _Citation {
  final int n;
  final String title;
  final String? url;
  final String sourceType; // 'law' | 'kgd_letter' | 'esep_platform' | 'blog' | ...
  final String quote;
  final String? article;
  final double trustWeight;

  const _Citation({
    required this.n,
    required this.title,
    required this.url,
    required this.sourceType,
    required this.quote,
    required this.article,
    required this.trustWeight,
  });

  factory _Citation.fromJson(Map<String, dynamic> j) => _Citation(
        n: (j['n'] ?? 0) as int,
        title: (j['title'] ?? '') as String,
        url: j['url'] as String?,
        sourceType: (j['source_type'] ?? 'unknown') as String,
        quote: (j['quote'] ?? '') as String,
        article: j['article']?.toString(),
        trustWeight: (j['trust_weight'] is num)
            ? (j['trust_weight'] as num).toDouble()
            : 0.5,
      );

  bool get isPlatform => sourceType == 'esep_platform';
  bool get isLaw      => sourceType == 'law';
  bool get isOfficial => trustWeight >= 0.9;

  String get badge {
    switch (sourceType) {
      case 'law':           return 'НК РК';
      case 'kgd_letter':    return 'КГД';
      case 'mfin_order':    return 'Минфин';
      case 'gov_decree':    return 'ППРК';
      case 'esep_platform': return 'Esep';
      case 'esep_glossary': return 'Глоссарий';
      case 'blog':          return 'Блог';
      case 'forum':         return 'Форум';
      case 'telegram':      return 'Канал';
      case 'youtube':       return 'Видео';
      default:              return 'Источник';
    }
  }
}

class _Message {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final String? answerId;
  final List<_Citation> citations;
  final List<String> followUp;
  final String? detectedLevel;

  const _Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.answerId,
    this.citations = const [],
    this.followUp = const [],
    this.detectedLevel,
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
  _ChatNotifier(this._ref) : super(const _ChatState());
  final Ref _ref;

  String _segmentFromMode() {
    final mode = _ref.read(userModeProvider);
    switch (mode) {
      case UserMode.ip:         return 'ip_solo';   // позже разделим solo / emp
      case UserMode.too:        return 'too';
      case UserMode.accountant: return 'accountant';
      default:                  return 'unknown';
    }
  }

  Future<void> send(String text, {String? screenContext}) async {
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
      final body = <String, dynamic>{
        'messages': apiMessages,
        'segment':  _segmentFromMode(),
        if (screenContext != null) 'screen_context': screenContext,
      };
      final data = await ApiClient.post('/ai-chat', body);

      final cits = (data['citations'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_Citation.fromJson)
          .toList();

      final follow = (data['follow_up'] as List? ?? const [])
          .whereType<String>()
          .toList();

      final reply = _Message(
        role: 'assistant',
        content: (data['reply'] ?? '') as String,
        timestamp: DateTime.now(),
        answerId: data['answer_id']?.toString(),
        citations: cits,
        followUp: follow,
        detectedLevel: data['detected_level']?.toString(),
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

  Future<void> sendFeedback(String answerId, String feedback,
      {String? note}) async {
    try {
      await ApiClient.post('/ai-chat/feedback', {
        'answer_id': answerId,
        'feedback':  feedback,
        if (note != null) 'note': note,
      });
    } catch (_) {/* silent */}
  }

  void clearChat() => state = const _ChatState();
}

final _chatProvider =
    StateNotifierProvider<_ChatNotifier, _ChatState>((ref) => _ChatNotifier(ref));

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
            Text('Консультант'),
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
            'Консультант',
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

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({required this.message, required this.isDark});
  final _Message message;
  final bool isDark;

  bool get isUser => message.role == 'user';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                        const SizedBox(height: 8),
                        _AssistantActions(message: message),
                      ],
                    ],
                  ),
                ),
                if (!isUser && message.citations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _CitationsRow(citations: message.citations),
                ],
                if (!isUser && message.followUp.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _FollowUpRow(items: message.followUp),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _AssistantActions extends ConsumerStatefulWidget {
  const _AssistantActions({required this.message});
  final _Message message;
  @override
  ConsumerState<_AssistantActions> createState() => _AssistantActionsState();
}

class _AssistantActionsState extends ConsumerState<_AssistantActions> {
  String? _given;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.message.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Скопировано'), duration: Duration(seconds: 1)),
            );
          },
          child: const Icon(Iconsax.copy, size: 14, color: EsepColors.textSecondary),
        ),
        if (widget.message.answerId != null) ...[
          const SizedBox(width: 12),
          InkWell(
            onTap: _given != null ? null : () {
              setState(() => _given = 'helpful');
              ref.read(_chatProvider.notifier)
                 .sendFeedback(widget.message.answerId!, 'helpful');
            },
            child: Icon(
              _given == 'helpful' ? Iconsax.like_15 : Iconsax.like_1,
              size: 14,
              color: _given == 'helpful' ? EsepColors.primary : EsepColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _given != null ? null : () {
              setState(() => _given = 'not_helpful');
              ref.read(_chatProvider.notifier)
                 .sendFeedback(widget.message.answerId!, 'not_helpful');
            },
            child: Icon(
              _given == 'not_helpful' ? Iconsax.dislike5 : Iconsax.dislike,
              size: 14,
              color: _given == 'not_helpful' ? EsepColors.expense : EsepColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Citations row ────────────────────────────────────────────────────────────

class _CitationsRow extends StatelessWidget {
  const _CitationsRow({required this.citations});
  final List<_Citation> citations;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: citations.map((c) => _CitationChip(citation: c)).toList(),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.citation});
  final _Citation citation;

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CitationDetailsSheet(citation: citation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = citation.isPlatform
        ? EsepColors.primary
        : citation.isOfficial
            ? const Color(0xFF1F7A3F)
            : const Color(0xFF8B5E00);

    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '[${citation.n}]',
              style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 11, color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              citation.badge,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
            if (citation.article != null) ...[
              const SizedBox(width: 4),
              Text(
                'ст. ${citation.article}',
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CitationDetailsSheet extends StatelessWidget {
  const _CitationDetailsSheet({required this.citation});
  final _Citation citation;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36, height: 4, margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: EsepColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: EsepColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        citation.badge,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: EsepColors.primary,
                        ),
                      ),
                    ),
                    if (citation.isOfficial) ...[
                      const SizedBox(width: 6),
                      const Icon(Iconsax.shield_tick, size: 14, color: Color(0xFF1F7A3F)),
                      const SizedBox(width: 2),
                      const Text('Официальный', style: TextStyle(fontSize: 11, color: Color(0xFF1F7A3F))),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    citation.title,
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: EsepColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: EsepColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: const Border(
                        left: BorderSide(color: EsepColors.primary, width: 3),
                      ),
                    ),
                    child: SelectableText(
                      citation.quote,
                      style: const TextStyle(
                        fontSize: 13, height: 1.6, color: EsepColors.textPrimary,
                      ),
                    ),
                  ),
                  if (citation.url != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final uri = Uri.tryParse(citation.url!);
                          if (uri != null) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Iconsax.export, size: 16),
                        label: const Text('Открыть оригинал'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Это объяснение на основе открытых источников. Не является юридической консультацией.',
                    style: TextStyle(fontSize: 11, color: EsepColors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Follow-up suggestions ────────────────────────────────────────────────────

class _FollowUpRow extends ConsumerWidget {
  const _FollowUpRow({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.take(3).map((q) {
        return ActionChip(
          label: Text(q, style: const TextStyle(fontSize: 12)),
          onPressed: () => ref.read(_chatProvider.notifier).send(q),
          backgroundColor: EsepColors.primary.withValues(alpha: 0.06),
          side: BorderSide(color: EsepColors.primary.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
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
