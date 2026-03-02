import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../services/hive_service.dart';

const _uuid = Uuid();

class TransactionNotifier extends StateNotifier<List<Transaction>> {
  TransactionNotifier() : super([]) {
    _load();
  }

  void _load() {
    state = HiveService.transactions.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

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
    await HiveService.transactions.put(tx.id, tx);
    _load();
  }

  Future<void> remove(String id) async {
    await HiveService.transactions.delete(id);
    _load();
  }

  Future<void> update(Transaction tx) async {
    await HiveService.transactions.put(tx.id, tx);
    _load();
  }
}

final transactionProvider =
    StateNotifierProvider<TransactionNotifier, List<Transaction>>((ref) {
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
