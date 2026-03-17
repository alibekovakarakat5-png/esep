import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/transaction.dart';
import '../theme/app_theme.dart';

// ── Demo mode flag ───────────────────────────────────────────────────────────

final isDemoProvider = StateProvider<bool>((ref) => false);

// ── Gate: show dialog when demo user tries to save ──────────────────────────

Future<void> showDemoGate(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Это демо-режим',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: const Text(
        'Зарегистрируйтесь бесплатно, чтобы сохранять данные, '
        'импортировать выписки и получать напоминания о дедлайнах.',
        style: TextStyle(fontSize: 14, color: EsepColors.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            context.go('/auth');
          },
          child: const Text('Создать аккаунт'),
        ),
      ],
    ),
  );
}

// ── Fake data for demo ──────────────────────────────────────────────────────

final now = DateTime.now();

List<Transaction> get demoTransactions => [
      Transaction(
        id: 'demo-1',
        title: 'ТОО АстанаТрейд',
        amount: 540000,
        isIncome: true,
        date: now.subtract(const Duration(days: 1)),
        clientName: 'ТОО АстанаТрейд',
        source: 'Kaspi',
        category: 'Продажи',
      ),
      Transaction(
        id: 'demo-2',
        title: 'Аренда офиса',
        amount: 120000,
        isIncome: false,
        date: now.subtract(const Duration(days: 2)),
        source: 'Halyk',
        category: 'Аренда',
      ),
      Transaction(
        id: 'demo-3',
        title: 'ИП Ахметова К.',
        amount: 285000,
        isIncome: true,
        date: now.subtract(const Duration(days: 3)),
        clientName: 'ИП Ахметова',
        source: 'Kaspi',
        category: 'Услуги',
      ),
      Transaction(
        id: 'demo-4',
        title: 'Интернет Beeline',
        amount: 9500,
        isIncome: false,
        date: now.subtract(const Duration(days: 4)),
        source: 'Kaspi',
        category: 'Связь',
      ),
      Transaction(
        id: 'demo-5',
        title: 'ТОО Стройком',
        amount: 320000,
        isIncome: true,
        date: now.subtract(const Duration(days: 5)),
        clientName: 'ТОО Стройком',
        source: 'Kaspi',
        category: 'Продажи',
      ),
      Transaction(
        id: 'demo-6',
        title: 'Канцтовары',
        amount: 15000,
        isIncome: false,
        date: now.subtract(const Duration(days: 6)),
        source: 'Kaspi',
        category: 'Офис',
      ),
      Transaction(
        id: 'demo-7',
        title: 'Оплата от Дидар',
        amount: 175000,
        isIncome: true,
        date: now.subtract(const Duration(days: 8)),
        clientName: 'Дидар ИП',
        source: 'Kaspi',
        category: 'Услуги',
      ),
      Transaction(
        id: 'demo-8',
        title: 'Коммунальные услуги',
        amount: 32000,
        isIncome: false,
        date: now.subtract(const Duration(days: 10)),
        source: 'Halyk',
        category: 'Коммунальные',
      ),
    ];
