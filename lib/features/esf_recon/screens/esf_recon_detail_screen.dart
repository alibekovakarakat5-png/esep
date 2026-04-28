import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'esf_recon_screen.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class _SessionDetail {
  final String id;
  final String title;
  final String periodFrom;
  final String periodTo;
  final String status;
  final String? registryFilename;
  final String? noticeFilename;
  final Map<String, dynamic> stats;

  const _SessionDetail({
    required this.id,
    required this.title,
    required this.periodFrom,
    required this.periodTo,
    required this.status,
    required this.registryFilename,
    required this.noticeFilename,
    required this.stats,
  });

  factory _SessionDetail.fromJson(Map<String, dynamic> j) => _SessionDetail(
        id: j['id'].toString(),
        title: (j['title'] ?? '') as String,
        periodFrom: (j['period_from'] ?? '').toString(),
        periodTo: (j['period_to'] ?? '').toString(),
        status: (j['status'] ?? 'draft') as String,
        registryFilename: j['registry_filename'] as String?,
        noticeFilename: j['notice_filename'] as String?,
        stats: (j['stats'] is Map) ? Map<String, dynamic>.from(j['stats']) : const {},
      );

  bool get hasRegistry => registryFilename != null;
  bool get hasNotice   => noticeFilename != null;
  bool get matched     => status == 'matched';
}

class _MatchResult {
  final String id;
  final String matchType;
  final Map<String, dynamic> diff;

  // ESF
  final String? esfInvoiceNo;
  final String? esfDate;
  final String? esfStatus;
  final String? esfSellerIin;
  final String? esfSellerName;
  final num? esfTotal;
  final num? esfVat;
  final String? registrationNo;

  // Notice
  final String? noticeInvoiceNo;
  final String? noticeDate;
  final String? noticeSellerIin;
  final String? noticeSellerName;
  final num? noticeTotal;
  final num? noticeVat;

  const _MatchResult({
    required this.id,
    required this.matchType,
    required this.diff,
    required this.esfInvoiceNo,
    required this.esfDate,
    required this.esfStatus,
    required this.esfSellerIin,
    required this.esfSellerName,
    required this.esfTotal,
    required this.esfVat,
    required this.registrationNo,
    required this.noticeInvoiceNo,
    required this.noticeDate,
    required this.noticeSellerIin,
    required this.noticeSellerName,
    required this.noticeTotal,
    required this.noticeVat,
  });

  factory _MatchResult.fromJson(Map<String, dynamic> j) => _MatchResult(
        id: j['id'].toString(),
        matchType: j['match_type'] as String,
        diff: (j['diff'] is Map) ? Map<String, dynamic>.from(j['diff']) : const {},
        esfInvoiceNo: j['esf_invoice_no'] as String?,
        esfDate: j['esf_date']?.toString(),
        esfStatus: j['esf_status'] as String?,
        esfSellerIin: j['esf_seller_iin'] as String?,
        esfSellerName: j['esf_seller_name'] as String?,
        esfTotal: j['esf_total'] as num?,
        esfVat: j['esf_vat'] as num?,
        registrationNo: j['registration_no'] as String?,
        noticeInvoiceNo: j['notice_invoice_no'] as String?,
        noticeDate: j['notice_date']?.toString(),
        noticeSellerIin: j['notice_seller_iin'] as String?,
        noticeSellerName: j['notice_seller_name'] as String?,
        noticeTotal: j['notice_total'] as num?,
        noticeVat: j['notice_vat'] as num?,
      );

  String get displayInvoice => esfInvoiceNo ?? noticeInvoiceNo ?? '—';
  String get displayDate    => (esfDate ?? noticeDate ?? '').split('T').first;
  String get displaySeller  => esfSellerName ?? noticeSellerName ?? esfSellerIin ?? noticeSellerIin ?? '—';
}

// ── Providers ────────────────────────────────────────────────────────────────

final _sessionDetailProvider =
    FutureProvider.family.autoDispose<_SessionDetail, String>((ref, id) async {
  final j = await ApiClient.get('/esf-recon/sessions/$id') as Map<String, dynamic>;
  return _SessionDetail.fromJson(j);
});

final _resultsProvider = FutureProvider.family
    .autoDispose<List<_MatchResult>, ({String id, String? type})>((ref, args) async {
  final qs = args.type == null ? '' : '?type=${args.type}';
  final list = await ApiClient.get('/esf-recon/sessions/${args.id}/results$qs') as List;
  return list.map((j) => _MatchResult.fromJson(j as Map<String, dynamic>)).toList();
});

// ── Screen ───────────────────────────────────────────────────────────────────

class EsfReconDetailScreen extends ConsumerStatefulWidget {
  const EsfReconDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<EsfReconDetailScreen> createState() => _EsfReconDetailScreenState();
}

class _EsfReconDetailScreenState extends ConsumerState<EsfReconDetailScreen> {
  String? _filterType; // null = все

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(_sessionDetailProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сверка'),
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (session) {
          return Column(
            children: [
              _UploadPanel(session: session, sessionId: widget.sessionId, onChanged: () {
                ref.invalidate(_sessionDetailProvider(widget.sessionId));
                ref.invalidate(_resultsProvider((id: widget.sessionId, type: _filterType)));
              }),
              if (session.matched) _StatsBar(stats: session.stats, onSelect: (t) {
                setState(() => _filterType = t);
              }, current: _filterType),
              Expanded(
                child: !session.matched
                  ? const _AwaitMatchHint()
                  : _ResultsList(sessionId: widget.sessionId, filterType: _filterType),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Upload panel ─────────────────────────────────────────────────────────────

class _UploadPanel extends ConsumerStatefulWidget {
  const _UploadPanel({required this.session, required this.sessionId, required this.onChanged});
  final _SessionDetail session;
  final String sessionId;
  final VoidCallback onChanged;
  @override
  ConsumerState<_UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends ConsumerState<_UploadPanel> {
  bool _busy = false;

  Future<void> _upload(String kind) async {
    final picked = await pickXlsxFile();
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      await uploadXlsx(
        path: '/esf-recon/sessions/${widget.sessionId}/$kind',
        filename: picked.name,
        bytes: picked.bytes,
      );
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл "${picked.name}" загружен')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: EsepColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runMatch() async {
    setState(() => _busy = true);
    try {
      await ApiClient.post('/esf-recon/sessions/${widget.sessionId}/match', {});
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: EsepColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final canMatch = s.hasRegistry || s.hasNotice;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: EsepColors.surface,
        border: Border(bottom: BorderSide(color: EsepColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('${s.periodFrom} — ${s.periodTo}',
              style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _FileSlot(
              icon: Iconsax.document_text_1,
              label: 'Реестр ЭСФ из esf.gov.kz',
              filename: s.registryFilename,
              onPick: _busy ? null : () => _upload('registry'),
            )),
            const SizedBox(width: 8),
            Expanded(child: _FileSlot(
              icon: Iconsax.document_filter,
              label: 'Извещение по ф. 300',
              filename: s.noticeFilename,
              onPick: _busy ? null : () => _upload('notice'),
            )),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Iconsax.refresh, size: 18),
              label: Text(s.matched ? 'Пересверить' : 'Сверить'),
              onPressed: (_busy || !canMatch) ? null : _runMatch,
            ),
          ),
          if (!canMatch)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Загрузите хотя бы один файл, чтобы начать сверку',
                style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileSlot extends StatelessWidget {
  const _FileSlot({required this.icon, required this.label,
      required this.filename, required this.onPick});
  final IconData icon;
  final String label;
  final String? filename;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final has = filename != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: has ? EsepColors.primary.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: has ? EsepColors.primary.withValues(alpha: 0.4) : EsepColors.divider,
            width: has ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: has ? EsepColors.primary : EsepColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              filename ?? 'Загрузить XLSX',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: has ? EsepColors.primary : EsepColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stats bar (фильтр-вкладки) ───────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats, required this.onSelect, required this.current});
  final Map<String, dynamic> stats;
  final void Function(String?) onSelect;
  final String? current;

  @override
  Widget build(BuildContext context) {
    int n(String k) => (stats[k] ?? 0) as int;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: EsepColors.divider)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _StatChip(label: 'Все', count: stats['total'] ?? 0,
              color: EsepColors.textSecondary,
              selected: current == null,
              onTap: () => onSelect(null)),
          _StatChip(label: 'Совпало', count: n('matched'),
              color: const Color(0xFF1F7A3F),
              selected: current == 'matched',
              onTap: () => onSelect('matched')),
          _StatChip(label: 'Сумма ≠', count: n('amount_diff'),
              color: const Color(0xFF8B5E00),
              selected: current == 'amount_diff',
              onTap: () => onSelect('amount_diff')),
          _StatChip(label: 'Отозвано', count: n('status_red'),
              color: EsepColors.expense,
              selected: current == 'status_red',
              onTap: () => onSelect('status_red')),
          _StatChip(label: 'Только в зачёте', count: n('only_notice'),
              color: EsepColors.expense,
              selected: current == 'only_notice',
              onTap: () => onSelect('only_notice')),
          _StatChip(label: 'Только в ЭСФ', count: n('only_esf'),
              color: const Color(0xFF8B5E00),
              selected: current == 'only_esf',
              onTap: () => onSelect('only_esf')),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.count,
      required this.color, required this.selected, required this.onTap});
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: ChoiceChip(
        label: Text('$label · $count', style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : color,
        )),
        selected: selected,
        showCheckmark: false,
        backgroundColor: color.withValues(alpha: 0.08),
        selectedColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

// ── Hint when match not yet done ─────────────────────────────────────────────

class _AwaitMatchHint extends StatelessWidget {
  const _AwaitMatchHint();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Загрузите файлы и нажмите "Сверить" — '
            'результат появится здесь.',
            textAlign: TextAlign.center,
            style: TextStyle(color: EsepColors.textSecondary, fontSize: 14, height: 1.6),
          ),
        ),
      );
}

// ── Results list ─────────────────────────────────────────────────────────────

class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.sessionId, required this.filterType});
  final String sessionId;
  final String? filterType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(_resultsProvider((id: sessionId, type: filterType)));
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (list) => list.isEmpty
          ? const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('В этой категории расхождений нет 👍',
                  style: TextStyle(color: EsepColors.textSecondary)),
            ))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: list.length,
              itemBuilder: (_, i) => _MatchTile(result: list[i]),
            ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.result});
  final _MatchResult result;

  ({Color color, String label, String hint}) _meta() {
    switch (result.matchType) {
      case 'matched':
        return (color: const Color(0xFF1F7A3F),
                label: 'Совпало',
                hint: 'Эта строка в зачёте подтверждена ЭСФ');
      case 'amount_diff':
        final delta = result.diff['vat_delta'];
        return (color: const Color(0xFF8B5E00),
                label: 'Сумма НДС не совпадает',
                hint: 'Разница ${delta != null ? "${delta} ₸" : ""}. Проверьте, кто прав.');
      case 'status_red':
        return (color: EsepColors.expense,
                label: 'ЭСФ отозван/аннулирован',
                hint: 'Эту строку нужно убрать из зачёта — иначе откажут.');
      case 'only_notice':
        return (color: EsepColors.expense,
                label: 'Только в извещении',
                hint: 'Этот ЭСФ от поставщика не получен. Под зачёт могут не пропустить.');
      case 'only_esf':
        return (color: const Color(0xFF8B5E00),
                label: 'Только в ЭСФ',
                hint: 'ЭСФ есть, в зачёт не попало — можно дозаявить.');
      default:
        return (color: EsepColors.textSecondary, label: result.matchType, hint: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(meta.label,
                    style: TextStyle(
                      color: meta.color,
                      fontSize: 11, fontWeight: FontWeight.w700,
                    )),
              ),
              const Spacer(),
              Text(result.displayDate,
                  style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
            ]),
            const SizedBox(height: 8),
            Text(result.displaySeller,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('Счёт-фактура № ${result.displayInvoice}',
                style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
            const SizedBox(height: 6),
            if (result.matchType == 'amount_diff')
              _AmountDiffRow(esf: result.esfVat, notice: result.noticeVat),
            const SizedBox(height: 6),
            Text(meta.hint,
                style: TextStyle(
                  fontSize: 12, color: meta.color, fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }
}

class _AmountDiffRow extends StatelessWidget {
  const _AmountDiffRow({required this.esf, required this.notice});
  final num? esf;
  final num? notice;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _Cell(label: 'НДС в ЭСФ', value: _fmt(esf))),
      const SizedBox(width: 8),
      Expanded(child: _Cell(label: 'НДС в зачёте', value: _fmt(notice))),
    ]);
  }

  static String _fmt(num? v) => v == null ? '—' : '${v.toStringAsFixed(2)} ₸';
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EsepColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: EsepColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
