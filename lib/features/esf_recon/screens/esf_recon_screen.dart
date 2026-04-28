import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class _EsfSession {
  final String id;
  final String title;
  final String periodFrom;
  final String periodTo;
  final String status;
  final String? registryFilename;
  final String? noticeFilename;
  final Map<String, dynamic> stats;
  final String createdAt;

  const _EsfSession({
    required this.id,
    required this.title,
    required this.periodFrom,
    required this.periodTo,
    required this.status,
    required this.registryFilename,
    required this.noticeFilename,
    required this.stats,
    required this.createdAt,
  });

  factory _EsfSession.fromJson(Map<String, dynamic> j) => _EsfSession(
        id: j['id'].toString(),
        title: (j['title'] ?? '') as String,
        periodFrom: (j['period_from'] ?? '').toString(),
        periodTo: (j['period_to'] ?? '').toString(),
        status: (j['status'] ?? 'draft') as String,
        registryFilename: j['registry_filename'] as String?,
        noticeFilename: j['notice_filename'] as String?,
        stats: (j['stats'] is Map) ? Map<String, dynamic>.from(j['stats']) : const {},
        createdAt: (j['created_at'] ?? '').toString(),
      );

  bool get isMatched => status == 'matched';
  int get matched      => (stats['matched'] ?? 0) as int;
  int get amountDiff   => (stats['amount_diff'] ?? 0) as int;
  int get statusRed    => (stats['status_red'] ?? 0) as int;
  int get onlyEsf      => (stats['only_esf'] ?? 0) as int;
  int get onlyNotice   => (stats['only_notice'] ?? 0) as int;
}

// ── Provider ─────────────────────────────────────────────────────────────────

final _sessionsProvider = FutureProvider.autoDispose<List<_EsfSession>>((ref) async {
  final list = await ApiClient.get('/esf-recon/sessions') as List;
  return list.map((j) => _EsfSession.fromJson(j as Map<String, dynamic>)).toList();
});

// ── Screen ───────────────────────────────────────────────────────────────────

class EsfReconScreen extends ConsumerWidget {
  const EsfReconScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(_sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сверка ЭСФ'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.info_circle),
            tooltip: 'Как пользоваться',
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Iconsax.add),
        label: const Text('Новая сверка'),
        onPressed: () => _newSessionDialog(context, ref),
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: e.toString(),
            onRetry: () => ref.invalidate(_sessionsProvider)),
        data: (list) => list.isEmpty
            ? _EmptyState(onCreate: () => _newSessionDialog(context, ref))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                itemCount: list.length,
                itemBuilder: (_, i) => _SessionCard(
                  session: list[i],
                  onTap: () => context.push('/esf-recon/${list[i].id}'),
                ),
              ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HelpSheet(),
    );
  }

  Future<void> _newSessionDialog(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final qStart = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
    final qEnd = DateTime(qStart.year, qStart.month + 3, 0);

    final fromCtrl = TextEditingController(text: _fmt(qStart));
    final toCtrl   = TextEditingController(text: _fmt(qEnd));
    final titleCtrl = TextEditingController(text: 'Сверка ${_fmtRu(qStart)} – ${_fmtRu(qEnd)}');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая сверка'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Название', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(
                  controller: fromCtrl,
                  decoration: const InputDecoration(
                    labelText: 'С (YYYY-MM-DD)', border: OutlineInputBorder(),
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: toCtrl,
                  decoration: const InputDecoration(
                    labelText: 'По (YYYY-MM-DD)', border: OutlineInputBorder(),
                  ),
                )),
              ]),
              const SizedBox(height: 12),
              const Text(
                'Сверка по ф.300 идёт поквартально. Можно указать произвольный период.',
                style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Создать')),
        ],
      ),
    );

    if (result == true) {
      try {
        final created = await ApiClient.post('/esf-recon/sessions', {
          'title': titleCtrl.text,
          'period_from': fromCtrl.text,
          'period_to': toCtrl.text,
        });
        ref.invalidate(_sessionsProvider);
        if (context.mounted) {
          context.push('/esf-recon/${created['id']}');
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }
}

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtRu(DateTime d) {
  const months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

// ── UI parts ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: EsepColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Iconsax.document_filter, size: 40, color: EsepColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('Сверка ЭСФ ↔ зачёт по НДС',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Загрузите реестр ЭСФ из esf.gov.kz и извещение по форме 300 — '
              'мы найдём расхождения, которые могут стоить вам зачёта по НДС.',
              style: TextStyle(fontSize: 14, color: EsepColors.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Iconsax.add),
              label: const Text('Создать первую сверку'),
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});
  final _EsfSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(session.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                _StatusChip(status: session.status),
              ]),
              const SizedBox(height: 4),
              Text('${session.periodFrom} — ${session.periodTo}',
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              if (session.isMatched) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: [
                    _MiniBadge(color: const Color(0xFF1F7A3F), label: '✓ ${session.matched}'),
                    if (session.amountDiff > 0)
                      _MiniBadge(color: const Color(0xFF8B5E00), label: 'Δ ${session.amountDiff}'),
                    if (session.statusRed > 0)
                      _MiniBadge(color: EsepColors.expense, label: '⚠ ${session.statusRed}'),
                    if (session.onlyNotice > 0)
                      _MiniBadge(color: EsepColors.expense, label: 'Только в зачёте: ${session.onlyNotice}'),
                    if (session.onlyEsf > 0)
                      _MiniBadge(color: const Color(0xFF8B5E00), label: 'Только в ЭСФ: ${session.onlyEsf}'),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                const Text('Загрузите файлы и запустите сверку',
                    style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final isMatched = status == 'matched';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isMatched ? const Color(0xFF1F7A3F) : EsepColors.warning)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isMatched ? 'Готово' : 'Черновик',
        style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: isMatched ? const Color(0xFF1F7A3F) : EsepColors.warning,
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: const [
            Text('Как сверить ЭСФ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 16),
            _Step(num: 1, title: 'Скачайте реестр входящих ЭСФ',
                body: 'Зайдите на esf.gov.kz, авторизуйтесь по ЭЦП. '
                      'Меню "Просмотр входящих ЭСФ" → выберите период → "Экспорт в Excel". '
                      'Сохраните XLSX-файл на компьютер.'),
            _Step(num: 2, title: 'Скачайте извещение по форме 300',
                body: 'Зайдите на cabinet.salyk.kz, откройте свою форму 300 за тот же квартал. '
                      'Внизу — "Скачать в Excel". Это файл со списком ЭСФ, которые вы отнесли в зачёт.'),
            _Step(num: 3, title: 'Создайте сверку в Esep',
                body: 'Кнопка "Новая сверка" → укажите период (обычно квартал) → загрузите оба файла. '
                      'Esep сравнит их и покажет 4 типа расхождений.'),
            _Step(num: 4, title: 'Разберите расхождения',
                body: 'Красные (только в извещении / отозванные ЭСФ) — срочно. '
                      'Жёлтые (расхождение по сумме) — посмотрите внимательно. '
                      'Зелёные совпадения трогать не нужно.'),
            SizedBox(height: 12),
            Text('О надёжности', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text(
              'Файлы обрабатываются на нашем сервере и не пересылаются третьим лицам. '
              'После закрытия сверки данные продолжают храниться в вашем аккаунте — можно вернуться '
              'и пересмотреть в любой момент.',
              style: TextStyle(fontSize: 13, color: EsepColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.num, required this.title, required this.body});
  final int num;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
              color: EsepColors.primary, shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(num.toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                      fontSize: 13, color: EsepColors.textSecondary, height: 1.5,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Iconsax.warning_2, size: 40, color: EsepColors.warning),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
        ]),
      );
}

// ── Public helper used by detail screen ──────────────────────────────────────

Future<dynamic> uploadXlsx({
  required String path,
  required String filename,
  required Uint8List bytes,
}) {
  return ApiClient.postMultipart(
    path,
    field: 'file',
    filename: filename,
    bytes: bytes,
    mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}

/// Открыть выбор файла на устройстве и вернуть имя + bytes.
Future<({String name, Uint8List bytes})?> pickXlsxFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
    withData: true,
  );
  final file = result?.files.singleOrNull;
  if (file == null || file.bytes == null) return null;
  return (name: file.name, bytes: file.bytes!);
}
