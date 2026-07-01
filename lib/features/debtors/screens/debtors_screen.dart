import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/models/client.dart';
import '../../../core/models/invoice.dart';
import '../../../core/providers/invoice_provider.dart';
import '../../../core/providers/client_provider.dart';
import '../../../core/providers/company_provider.dart';
import '../../../shared/widgets/beta_feedback_button.dart';
import '../../../shared/widgets/beta_chip.dart';
import '../../../core/providers/reconcile_provider.dart';

/// Цвет бренда WhatsApp — для кнопки напоминания об оплате.
const _waGreen = Color(0xFF25D366);

/// Экран «Кто мне должен» — дебиторка поверх неоплаченных счетов.
/// Один из ключевых ежедневных экранов (по модели Vyapar): видишь, кто и
/// сколько должен, и в один тап шлёшь напоминание в WhatsApp.
class DebtorsScreen extends ConsumerWidget {
  const DebtorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,##0', 'ru_RU');
    final debtors = ref.watch(debtorsProvider);
    final clients = ref.watch(clientProvider);
    final company = ref.watch(companyProvider);
    final matches = ref.watch(paymentMatchesProvider);

    final total = debtors.fold(0.0, (s, d) => s + d.totalOwed);
    final overdueCount = debtors.where((d) => d.hasOverdue).length;

    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Кто мне должен'),
          SizedBox(width: 8),
          BetaChip(),
        ]),
        actions: const [
          BetaFeedbackButton(screen: 'debtors', compact: true),
          SizedBox(width: 4),
        ],
      ),
      body: debtors.isEmpty
          ? _EmptyState()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (matches.isNotEmpty) ...[
                  _ReconcileBanner(
                    count: matches.length,
                    onTap: () => _openReconcile(context, ref, fmt),
                  ),
                  const SizedBox(height: 12),
                ],
                _SummaryCard(
                  total: total,
                  debtorCount: debtors.length,
                  overdueCount: overdueCount,
                  fmt: fmt,
                ),
                const SizedBox(height: 16),
                ...debtors.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DebtorCard(
                        debtor: d,
                        phone: _phoneFor(d, clients),
                        fmt: fmt,
                        onRemind: () => _remind(
                            context, d, _phoneFor(d, clients), company.name, fmt),
                        onOpen: () =>
                            _showInvoices(context, ref, d, fmt),
                      ),
                    )),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  /// Находит телефон клиента: сперва по clientId, затем по имени.
  static String? _phoneFor(Debtor d, List<Client> clients) {
    Client? c;
    if (d.clientId != null && d.clientId!.isNotEmpty) {
      for (final cl in clients) {
        if (cl.id == d.clientId) {
          c = cl;
          break;
        }
      }
    }
    c ??= () {
      for (final cl in clients) {
        if (cl.name.trim().toLowerCase() == d.clientName.trim().toLowerCase()) {
          return cl;
        }
      }
      return null;
    }();
    return c?.phone;
  }

  /// Нормализует казахстанский номер под формат wa.me (только цифры, код 7).
  static String? _waPhone(String? raw) {
    if (raw == null) return null;
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
    if (d.length == 10) d = '7$d'; // без кода страны
    if (d.length == 11 && d.startsWith('7')) return d;
    return d.length >= 11 ? d : null;
  }

  static String _reminderText(Debtor d, String company, NumberFormat fmt) {
    final sum = '${fmt.format(d.totalOwed)} ₸';
    final b = StringBuffer();
    b.writeln('Здравствуйте!');
    if (d.invoiceCount == 1) {
      b.writeln('Напоминаю об оплате счёта на сумму $sum.');
    } else {
      b.writeln(
          'Напоминаю об оплате ${d.invoiceCount} ${_invoiceWord(d.invoiceCount)} на сумму $sum.');
    }
    b.writeln('Если уже оплатили — спасибо, не обращайте внимания.');
    if (company.trim().isNotEmpty) b.write('С уважением, ${company.trim()}');
    return b.toString();
  }

  static Future<void> _remind(BuildContext context, Debtor d, String? phone,
      String company, NumberFormat fmt) async {
    final wa = _waPhone(phone);
    final messenger = ScaffoldMessenger.of(context);
    if (wa == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'У клиента не указан телефон — добавьте номер в карточке клиента'),
      ));
      return;
    }
    final text = _reminderText(d, company, fmt);
    final uri = Uri.parse('https://wa.me/$wa?text=${Uri.encodeComponent(text)}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Не удалось открыть WhatsApp')));
      }
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось открыть WhatsApp')));
    }
  }

  static void _showInvoices(
      BuildContext context, WidgetRef ref, Debtor d, NumberFormat fmt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DebtorInvoicesSheet(
        clientId: d.clientId,
        clientName: d.clientName,
        fmt: fmt,
      ),
    );
  }

  static String _invoiceWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'счёт';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'счёта';
    }
    return 'счетов';
  }

  static String _clientWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'клиент';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'клиента';
    }
    return 'клиентов';
  }
}

// ── Авто-сверка оплат (бета): поступления ↔ неоплаченные счета ───────────────
void _openReconcile(BuildContext context, WidgetRef ref, NumberFormat fmt) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReconcileSheet(fmt: fmt),
  );
}

class _ReconcileBanner extends StatelessWidget {
  const _ReconcileBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  static String _word(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'счёт';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'счёта';
    return 'счетов';
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EsepColors.income.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EsepColors.income.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Iconsax.money_recive, color: EsepColors.income, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text('Похоже, оплачено: $count ${_word(count)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: EsepColors.income)),
                    ),
                    const SizedBox(width: 6),
                    const BetaChip(),
                  ]),
                  const SizedBox(height: 2),
                  const Text('Нашли поступления по сумме — сверить и закрыть',
                      style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                ]),
              ),
              const Icon(Iconsax.arrow_right_3, color: EsepColors.textDisabled, size: 18),
            ]),
          ),
        ),
      );
}

class _ReconcileSheet extends ConsumerWidget {
  const _ReconcileSheet({required this.fmt});
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(paymentMatchesProvider);
    return Container(
      decoration: const BoxDecoration(
        color: EsepColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(color: EsepColors.divider, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Сверка оплат', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(width: 8),
          BetaChip(),
        ]),
        const SizedBox(height: 4),
        const Text('Похоже, эти счета уже оплачены. Проверьте и подтвердите.',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Всё сверено 🎉', style: TextStyle(fontSize: 14, color: EsepColors.textSecondary)),
          )
        else ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: SingleChildScrollView(
              child: Column(
                children: matches
                    .map((m) => _MatchRow(
                          match: m,
                          fmt: fmt,
                          onConfirm: () => _markPaid(context, ref, m.invoice),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _markAll(context, ref, matches),
              icon: const Icon(Iconsax.tick_circle, size: 18),
              label: Text('Отметить все ${matches.length} оплаченными'),
              style: FilledButton.styleFrom(
                backgroundColor: EsepColors.income,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref, Invoice inv) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(invoiceProvider.notifier).updateStatus(inv.id, InvoiceStatus.paid);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Не удалось обновить счёт')));
    }
  }

  Future<void> _markAll(BuildContext context, WidgetRef ref, List<PaymentMatch> ms) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final m in ms) {
        await ref.read(invoiceProvider.notifier).updateStatus(m.invoice.id, InvoiceStatus.paid);
      }
      messenger.showSnackBar(SnackBar(content: Text('Отмечено оплаченными: ${ms.length}')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Не все счета удалось обновить')));
    }
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.fmt, required this.onConfirm});
  final PaymentMatch match;
  final NumberFormat fmt;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final inv = match.invoice;
    final pay = match.payment;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EsepColors.divider),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${inv.number} · ${inv.clientName}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(
              '↳ поступление ${fmt.format(pay.amount)} ₸ · ${DateFormat('dd MMM', 'ru_RU').format(pay.date)}${pay.source != null ? ' · ${pay.source}' : ''}',
              style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            if (match.nameMatch) ...[
              const SizedBox(height: 2),
              const Text('✓ имя клиента совпало',
                  style: TextStyle(fontSize: 10, color: EsepColors.income, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onConfirm,
          style: TextButton.styleFrom(foregroundColor: EsepColors.income),
          child: const Text('Оплачен', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ── Пустое состояние ────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Iconsax.tick_circle, color: EsepColors.income, size: 56),
          SizedBox(height: 14),
          Text('Никто не должен',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: EsepColors.textPrimary)),
          SizedBox(height: 4),
          Text('Все выставленные счета оплачены',
              style: TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
        ]),
      );
}

// ── Сводка сверху ───────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.debtorCount,
    required this.overdueCount,
    required this.fmt,
  });
  final double total;
  final int debtorCount;
  final int overdueCount;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            EsepColors.primary.withValues(alpha: 0.10),
            EsepColors.info.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EsepColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Вам должны',
            style: TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
        const SizedBox(height: 4),
        Text('${fmt.format(total)} ₸',
            style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: EsepColors.textPrimary)),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Iconsax.people, size: 16, color: EsepColors.textSecondary),
          const SizedBox(width: 6),
          Text('$debtorCount ${DebtorsScreen._clientWord(debtorCount)}',
              style: const TextStyle(
                  fontSize: 13, color: EsepColors.textSecondary)),
          if (overdueCount > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: EsepColors.expense.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$overdueCount просрочено',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EsepColors.expense)),
            ),
          ],
        ]),
      ]),
    );
  }
}

// ── Карточка должника ───────────────────────────────────────────────────────
class _DebtorCard extends StatelessWidget {
  const _DebtorCard({
    required this.debtor,
    required this.phone,
    required this.fmt,
    required this.onRemind,
    required this.onOpen,
  });
  final Debtor debtor;
  final String? phone;
  final NumberFormat fmt;
  final VoidCallback onRemind;
  final VoidCallback onOpen;

  String _subtitle() {
    final parts = <String>[
      '${debtor.invoiceCount} ${DebtorsScreen._invoiceWord(debtor.invoiceCount)}'
    ];
    if (debtor.hasOverdue) {
      if (debtor.oldestDue != null) {
        final days = DateTime.now().difference(debtor.oldestDue!).inDays;
        parts.add(days > 0 ? 'просрочено $days дн' : 'просрочено');
      } else {
        parts.add('просрочено');
      }
    } else if (debtor.oldestDue != null) {
      parts.add('оплата до ${DateFormat('dd MMM', 'ru_RU').format(debtor.oldestDue!)}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final amountColor =
        debtor.hasOverdue ? EsepColors.expense : EsepColors.textPrimary;
    final letter = debtor.clientName.trim().isNotEmpty
        ? debtor.clientName.trim().substring(0, 1).toUpperCase()
        : '?';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(children: [
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: EsepColors.primary.withValues(alpha: 0.15),
                child: Text(letter,
                    style: const TextStyle(
                        color: EsepColors.primary,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(debtor.clientName,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(_subtitle(),
                          style: TextStyle(
                              fontSize: 12,
                              color: debtor.hasOverdue
                                  ? EsepColors.expense
                                  : EsepColors.textSecondary)),
                    ]),
              ),
              const SizedBox(width: 8),
              Text('${fmt.format(debtor.totalOwed)} ₸',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: amountColor)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRemind,
                  icon: const Icon(Iconsax.message, size: 16, color: _waGreen),
                  label: const Text('Напомнить',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _waGreen)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _waGreen),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Iconsax.receipt_item,
                      size: 16, color: EsepColors.primary),
                  label: const Text('Счета',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: EsepColors.primary)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Лист со счетами должника + отметка «оплачено» ───────────────────────────
class _DebtorInvoicesSheet extends ConsumerWidget {
  const _DebtorInvoicesSheet({
    required this.clientId,
    required this.clientName,
    required this.fmt,
  });
  final String? clientId;
  final String clientName;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Перечитываем debtorsProvider — после отметки «оплачено» список обновится.
    final debtors = ref.watch(debtorsProvider);
    Debtor? debtor;
    for (final d in debtors) {
      final sameId = clientId != null &&
          clientId!.isNotEmpty &&
          d.clientId == clientId;
      final sameName = (clientId == null || clientId!.isEmpty) &&
          d.clientName.trim().toLowerCase() == clientName.trim().toLowerCase();
      if (sameId || sameName) {
        debtor = d;
        break;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: EsepColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: EsepColors.divider,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(clientName,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (debtor == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Все счета оплачены 🎉',
                style:
                    TextStyle(fontSize: 14, color: EsepColors.textSecondary)),
          )
        else ...[
          Text('Долг: ${fmt.format(debtor.totalOwed)} ₸',
              style: const TextStyle(
                  fontSize: 13, color: EsepColors.textSecondary)),
          const SizedBox(height: 12),
          ...debtor.invoices.map((inv) => _InvoiceRow(
                invoice: inv,
                fmt: fmt,
                onPaid: () => _markPaid(context, ref, inv),
              )),
        ],
      ]),
    );
  }

  Future<void> _markPaid(
      BuildContext context, WidgetRef ref, Invoice inv) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(invoiceProvider.notifier)
          .updateStatus(inv.id, InvoiceStatus.paid);
      messenger.showSnackBar(SnackBar(
          content: Text('Счёт ${inv.number} отмечен оплаченным')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось обновить счёт')));
    }
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.fmt,
    required this.onPaid,
  });
  final Invoice invoice;
  final NumberFormat fmt;
  final VoidCallback onPaid;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = invoice.status == InvoiceStatus.overdue ||
        (invoice.dueDate != null && invoice.dueDate!.isBefore(now));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(invoice.number,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [
                DateFormat('dd MMM yyyy', 'ru_RU').format(invoice.createdAt),
                if (overdue) 'просрочено',
              ].join(' · '),
              style: TextStyle(
                  fontSize: 11,
                  color:
                      overdue ? EsepColors.expense : EsepColors.textSecondary),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text('${fmt.format(invoice.totalAmount)} ₸',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onPaid,
          style: TextButton.styleFrom(
            foregroundColor: EsepColors.income,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
          ),
          child: const Text('Оплачено', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}
