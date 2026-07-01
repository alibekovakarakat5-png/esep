import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invoice.dart';
import '../models/transaction.dart';
import 'invoice_provider.dart';
import 'transaction_provider.dart';

/// Предполагаемое совпадение: неоплаченный счёт ↔ входящее поступление.
class PaymentMatch {
  final Invoice invoice;
  final Transaction payment;

  /// true → имя клиента в поступлении совпало с клиентом счёта (выше уверенность).
  final bool nameMatch;

  const PaymentMatch({
    required this.invoice,
    required this.payment,
    required this.nameMatch,
  });
}

bool _namesMatch(String a, String b) {
  final x = a.trim().toLowerCase();
  final y = b.trim().toLowerCase();
  if (x.isEmpty || y.isEmpty || y.length < 3) return false;
  return x.contains(y) || y.contains(x);
}

/// Авто-сверка оплат (БЕТА). Сопоставляет неоплаченные счета (sent/overdue) с
/// входящими поступлениями из операций/банк-импорта по правилам:
///  - точная сумма (±1 ₸),
///  - дата поступления не раньше выставления счёта (допуск 1 день),
///  - одно поступление — не более чем на один счёт (greedy, старые счета первыми).
/// Совпадение имени клиента лишь повышает уверенность (nameMatch), но не требуется.
///
/// ⚠️ НЕ отмечает счёт оплаченным сам — только предлагает совпадения на
/// подтверждение пользователю (защита от ложных срабатываний).
final paymentMatchesProvider = Provider<List<PaymentMatch>>((ref) {
  final unpaid = ref.watch(unpaidInvoicesProvider);
  final incomes =
      ref.watch(transactionProvider).where((t) => t.isIncome).toList();
  if (unpaid.isEmpty || incomes.isEmpty) return const [];

  final used = <String>{};
  final matches = <PaymentMatch>[];
  final invs = [...unpaid]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  for (final inv in invs) {
    final total = inv.totalAmount;
    if (total <= 0) continue;

    Transaction? best;
    var bestName = false;
    for (final t in incomes) {
      if (used.contains(t.id)) continue;
      if ((t.amount - total).abs() >= 1.0) continue; // точная сумма
      if (t.date.isBefore(inv.createdAt.subtract(const Duration(days: 1)))) {
        continue; // поступление раньше счёта — не оно
      }
      final nm = _namesMatch(inv.clientName, t.clientName ?? t.title);
      // Предпочитаем совпадение по имени; иначе берём первое по сумме.
      if (best == null || (nm && !bestName)) {
        best = t;
        bestName = nm;
      }
    }

    if (best != null) {
      used.add(best.id);
      matches.add(PaymentMatch(invoice: inv, payment: best, nameMatch: bestName));
    }
  }
  return matches;
});
