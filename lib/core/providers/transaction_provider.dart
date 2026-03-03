import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

const _uuid = Uuid();

class TransactionNotifier extends StateNotifier<List<Transaction>> {
  TransactionNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.get('/transactions') as List<dynamic>;
      state = data
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      state = [];
    }
  }

  Future<void> reload() => _load();

  Future<void> add({
    required String title,
    required double amount,
    required bool isIncome,
    required DateTime date,
    String? clientName,
    String? source,
    String? note,
    String? category,
  }) async {
    final tx = Transaction(
      id: _uuid.v4(),
      title: title,
      amount: amount,
      isIncome: isIncome,
      date: date,
      clientName: clientName,
      source: source,
      note: note,
      category: category,
    );
    await ApiClient.post('/transactions', tx.toJson());
    await _load();
  }

  Future<void> remove(String id) async {
    await ApiClient.delete('/transactions/$id');
    await _load();
  }

  Future<void> update(Transaction tx) async {
    await ApiClient.put('/transactions/${tx.id}', tx.toJson());
    await _load();
  }
}

final transactionProvider =
    StateNotifierProvider<TransactionNotifier, List<Transaction>>((ref) {
  // Reload when auth changes
  ref.watch(authProvider);
  return TransactionNotifier();
});

// Derived providers

final incomeTransactionsProvider = Provider<List<Transaction>>((ref) {
  return ref.watch(transactionProvider).where((t) => t.isIncome).toList();
});

final expenseTransactionsProvider = Provider<List<Transaction>>((ref) {
  return ref.watch(transactionProvider).where((t) => !t.isIncome).toList();
});

/// Total income for current half-year
final halfYearIncomeProvider = Provider<double>((ref) {
  final now = DateTime.now();
  final halfStart = now.month <= 6
      ? DateTime(now.year, 1, 1)
      : DateTime(now.year, 7, 1);
  return ref
      .watch(transactionProvider)
      .where((t) => t.isIncome && t.date.isAfter(halfStart))
      .fold(0.0, (sum, t) => sum + t.amount);
});

/// Total expense for current month
final monthExpenseProvider = Provider<double>((ref) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  return ref
      .watch(transactionProvider)
      .where((t) => !t.isIncome && t.date.isAfter(monthStart))
      .fold(0.0, (sum, t) => sum + t.amount);
});

/// Total income for current month
final monthIncomeProvider = Provider<double>((ref) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  return ref
      .watch(transactionProvider)
      .where((t) => t.isIncome && t.date.isAfter(monthStart))
      .fold(0.0, (sum, t) => sum + t.amount);
});

/// Monthly income + expense for the last 6 months (oldest → newest)
final monthlyChartProvider = Provider<List<MonthlyData>>((ref) {
  final txs = ref.watch(transactionProvider);
  final now = DateTime.now();
  return List.generate(6, (i) {
    final monthOffset = 5 - i;
    var m = now.month - monthOffset;
    var y = now.year;
    while (m <= 0) { m += 12; y--; }
    final start = DateTime(y, m, 1);
    final end = DateTime(y, m + 1, 1);
    double income = 0, expense = 0;
    for (final t in txs) {
      if (!t.date.isBefore(start) && t.date.isBefore(end)) {
        if (t.isIncome) { income += t.amount; } else { expense += t.amount; }
      }
    }
    return MonthlyData(income: income, expense: expense, label: _shortMonth(m));
  });
});

class MonthlyData {
  final double income;
  final double expense;
  final String label;
  const MonthlyData({required this.income, required this.expense, required this.label});
}

String _shortMonth(int m) {
  const names = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
  return names[(m - 1) % 12];
}
