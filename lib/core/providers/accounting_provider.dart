import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/accounting_client.dart';
import '../constants/kz_tax_constants.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';
import 'demo_provider.dart';

const _uuid = Uuid();

// ── Demo data ─────────────────────────────────────────────────────────────────

List<AccountingClient> _demoClients() {
  final now = DateTime.now();
  final monthLabel = '${_monthName(now.month)} ${now.year}';
  return [
    AccountingClient(
      id: 'demo-1',
      name: 'Ахметов Серик Болатович',
      binOrIin: '850304300421',
      entityType: ClientEntityType.ip,
      regime: ClientTaxRegime.simplified910,
      employees: [
        const Employee(id: 'e1', name: 'Иванов А.А.', salary: 150000),
      ],
      monthlyFee: 15000,
      feeReceivedThisMonth: false,
      checklist: [
        DocChecklistItem(
            id: 'd1',
            label: 'Банковская выписка за $monthLabel',
            received: true),
        DocChecklistItem(
            id: 'd2', label: 'Реестр доходов за $monthLabel', received: false),
      ],
    ),
    AccountingClient(
      id: 'demo-2',
      name: 'ТОО "Астана Строй"',
      binOrIin: '200540013422',
      entityType: ClientEntityType.too,
      regime: ClientTaxRegime.our,
      employees: [
        const Employee(id: 'e2', name: 'Сейткалиев Д.', salary: 200000),
        const Employee(id: 'e3', name: 'Нурова А.К.', salary: 120000),
        const Employee(id: 'e4', name: 'Жаксыбеков Р.', salary: 180000),
      ],
      monthlyFee: 35000,
      feePayments: [
        FeePayment(month: feeMonthKey(now), amount: 35000, received: true)
      ],
      checklist: [
        DocChecklistItem(
            id: 'd3',
            label: 'Банковская выписка за $monthLabel',
            received: true),
        DocChecklistItem(
            id: 'd4', label: 'Авансовые отчёты за $monthLabel', received: true),
        const DocChecklistItem(
            id: 'd5', label: 'Акты выполненных работ', received: true),
        DocChecklistItem(
            id: 'd6', label: 'Счёт-фактуры за $monthLabel', received: false),
      ],
    ),
    AccountingClient(
      id: 'demo-3',
      name: 'Сейткали Айгерим',
      binOrIin: '920615400218',
      entityType: ClientEntityType.ip,
      regime: ClientTaxRegime.simplified910,
      employees: [],
      monthlyFee: 8000,
      feePayments: [
        FeePayment(month: feeMonthKey(now), amount: 8000, received: true)
      ],
      checklist: [
        DocChecklistItem(
            id: 'd7',
            label: 'Выписка по счёту за $monthLabel',
            received: false),
      ],
    ),
    AccountingClient(
      id: 'demo-4',
      name: 'Нурланов Дидар Маратович',
      binOrIin: '910922400312',
      entityType: ClientEntityType.ip,
      regime: ClientTaxRegime.simplified910,
      employees: [],
      monthlyFee: 10000,
      feeReceivedThisMonth: false,
      checklist: [
        DocChecklistItem(
            id: 'd8', label: 'Реестр доходов за $monthLabel', received: true),
      ],
    ),
    AccountingClient(
      id: 'demo-5',
      name: 'ТОО "Алтын Апта"',
      binOrIin: '180940022513',
      entityType: ClientEntityType.too,
      regime: ClientTaxRegime.simplified910,
      employees: [
        const Employee(id: 'e5', name: 'Каримов Б.', salary: 130000),
        const Employee(id: 'e6', name: 'Дюсенова М.', salary: 110000),
      ],
      monthlyFee: 20000,
      feePayments: [
        FeePayment(month: feeMonthKey(now), amount: 20000, received: true)
      ],
      checklist: [
        DocChecklistItem(
            id: 'd9',
            label: 'Банковская выписка за $monthLabel',
            received: true),
        DocChecklistItem(
            id: 'd10', label: 'Реестр доходов за $monthLabel', received: true),
      ],
    ),
  ];
}

// ── Deadline Generator ────────────────────────────────────────────────────────

/// Генерирует все дедлайны клиента в окне [from, from+days]
List<ClientDeadline> generateClientDeadlines(
  AccountingClient client,
  DateTime from,
  int days,
) {
  final deadlines = <ClientDeadline>[];
  final start = DateTime(from.year, from.month, from.day);
  final to = start.add(Duration(days: days));
  if (!client.isActive || days <= 0) return deadlines;
  // Removed regimes must not generate current reminders.
  if (from.year >= 2026 &&
      (client.regime == ClientTaxRegime.esp ||
          client.regime == ClientTaxRegime.patent)) {
    return deadlines;
  }

  void add(String type, String label, DateTime date) {
    // Official 2026 five-day calendar; future years need calendar confirmation.
    final holidays2026 = <String>{
      '1-1',
      '1-2',
      '1-7',
      '3-8',
      '3-9',
      '3-21',
      '3-22',
      '3-23',
      '3-24',
      '3-25',
      '5-1',
      '5-7',
      '5-9',
      '5-11',
      '5-27',
      '7-6',
      '10-25',
      '10-26',
      '12-16',
    };
    while (date.weekday >= DateTime.saturday ||
        (date.year == 2026 &&
            holidays2026.contains('${date.month}-${date.day}'))) {
      date = date.add(const Duration(days: 1));
    }
    if (!date.isBefore(start) && date.isBefore(to)) {
      deadlines.add(ClientDeadline(
        clientId: client.id,
        clientName: client.name,
        type: type,
        label:
            date.year == 2026 ? label : '$label · уточните календарь переносов',
        date: date,
      ));
    }
  }

  // Перебираем месяцы в окне
  for (int offset = -1; offset <= (days ~/ 28) + 2; offset++) {
    final m = _addMonths(from, offset);
    final year = m.year;
    final month = m.month;

    switch (client.regime) {
      case ClientTaxRegime.simplified910:
      case ClientTaxRegime.patent:
        // Соцплатежи — до 25-го каждого месяца
        final previous = DateTime(year, month - 1);
        add(
            'social',
            'Соцплатежи · ${_monthName(previous.month)} ${previous.year} (при наличии обязанности)',
            DateTime(year, month, 25));

        // 910 форма — 15 февраля и 15 августа
        if (client.regime == ClientTaxRegime.simplified910) {
          add('910', '910 форма за II полугодие ${year - 1}',
              DateTime(year, 2, 15));
          add('910', '910 форма за I полугодие $year', DateTime(year, 8, 15));
        }

      case ClientTaxRegime.esp:
        // ЕСП — до 25-го каждого месяца
        // Legacy regime has no current obligations generated automatically.
        break;

      case ClientTaxRegime.our:
        // Зарплатные налоги — до 25-го
        final previous = DateTime(year, month - 1);
        if (client.employees.isNotEmpty) {
          add(
              'payroll',
              'ИПН/ОПВ/СО сотрудников · ${_monthName(previous.month)} ${previous.year}',
              DateTime(year, month, 25));
        }

        // Quarter end + second month: Q1 May, Q2 August, Q3 November, Q4 February.
        for (final qMonth in [2, 5, 8, 11]) {
          final periodYear = qMonth == 2 ? year - 1 : year;
          final quarter = qMonth == 2 ? 4 : (qMonth - 2) ~/ 3;
          add(
              '200',
              '200.00 за $quarter кв. $periodYear${client.employees.isEmpty ? ' (уточните обязанность налогового агента)' : ''}',
              DateTime(year, qMonth, 15));
        }

        // 700.00 — налог на имущество/транспорт/землю (НЕ КПН, КПН это форма
        // 100). Срок — 31 марта года, следующего за отчётным.
        add(
            '700',
            'Форма 700.00 за ${year - 1} (при наличии объектов налогообложения)',
            DateTime(year, 3, 31));
    }
  }

  // Убираем дубликаты по (type, date)
  final seen = <String>{};
  deadlines
      .retainWhere((d) => seen.add('${d.type}_${d.date.toIso8601String()}'));

  deadlines.sort((a, b) => a.date.compareTo(b.date));
  return deadlines;
}

/// Ближайший дедлайн клиента
ClientDeadline? nearestDeadline(AccountingClient client) {
  final now = DateTime.now();
  final deadlines = generateClientDeadlines(client, now, 90);
  return deadlines.where((d) => !d.isPast).firstOrNull;
}

// ── Employee Social Calc ──────────────────────────────────────────────────────

EmployeeSocialCalc calcEmployeeSocial(Employee emp) {
  final salary = emp.salary;
  final mzp = KzTax.currentMzp;

  // ОПВ: 10% от зарплаты, max база = 50 МЗП (ст. 25 Закона о пенсионном обеспечении)
  final opvBase = salary.clamp(0, mzp * 50);
  final opv = opvBase * KzTax.employeeOpvRate;

  // ВОСМС (сотрудника): 2%, max база = 20 МЗП (ст. 28 Закона о ОСМС, ред. 2026)
  final vosmsSelfBase = salary.clamp(0, KzTax.employeeVosmsMaxBase);
  final vosmsSelf = vosmsSelfBase * KzTax.employeeVosmsRate;

  // ИПН: 10% от (зарплата − ОПВ − ВОСМС − 30 МРП).
  // Вычет социальных платежей (ОПВ и ВОСМС) — ст. 401 НК РК (Закон 214-VIII);
  // ВОСМС раньше в базу не попадал, из-за чего ИПН был завышен на 0.2%
  // оклада (500 ₸ при 250 000). Эталон: test/payroll_ipn_test.dart.
  final standardDeduction = KzTax.ipnMonthlyDeduction;
  final ipnBase =
      (salary - opv - vosmsSelf - standardDeduction).clamp(0, double.infinity);
  final ipn = ipnBase * 0.10;

  // ОПВР (работодатель): 3.5% (2026), max база = 50 МЗП (ст. 26-1 Закона о пенсионном обеспечении)
  final opvrBase = salary.clamp(0, mzp * 50);
  final opvr = opvrBase * KzTax.employerOpvrRate;

  // СО (работодатель): 5% от (зарплата - ОПВ), min МЗП, max 7 МЗП (ст. 15 Закона о СО)
  final soBase = (salary - opv).clamp(mzp, mzp * 7);
  final so = soBase * KzTax.employerSoRate;

  // ООСМС (работодатель): 3%, max база = 40 МЗП (ст. 27 Закона о ОСМС, ред. 2026)
  final vosmsBase = salary.clamp(0, KzTax.employerVosmsMaxBase);
  final vosms = vosmsBase * KzTax.employerVosmsRate;

  return EmployeeSocialCalc(
    employee: emp,
    opv: opv,
    ipn: ipn,
    opvr: opvr,
    so: so,
    vosms: vosms,
    vosmsSelf: vosmsSelf,
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final accountingLoadingProvider = StateProvider<bool>((ref) => true);

// Injectable persistence boundary: regression tests can simulate a delayed or
// failed request without contacting production.
final accountingClientWriterProvider =
    Provider<Future<void> Function(AccountingClient)>((ref) => (client) async {
          await ApiClient.post('/accounting/clients', client.toJson());
        });

class AccountingNotifier extends StateNotifier<List<AccountingClient>> {
  final Set<String> _pendingFees = {};
  final Ref _ref;
  AccountingNotifier(this._ref) : super([]) {
    // Как у transactions/invoices: грузим только после входа, иначе запрос
    // уходит без токена и получает 401. Провайдер пересоздаётся при смене
    // authProvider (ref.watch ниже), поэтому загрузка стартует сама.
    if (_ref.read(authProvider) == AuthState.authenticated) {
      Future.microtask(_load);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    // Демо-режим: показываем клиентов-примеров, чтобы экран не был пустым
    // на презентации. В обычном режиме демо-данных быть не должно —
    // бухгалтер увидел бы чужие вымышленные ИП вместо своих клиентов.
    if (_ref.read(isDemoProvider)) {
      state = _demoClients();
      _ref.read(accountingLoadingProvider.notifier).state = false;
      return;
    }
    _ref.read(accountingLoadingProvider.notifier).state = true;
    try {
      final data = await ApiClient.get('/accounting/clients') as List<dynamic>;
      if (!mounted) return;
      state = data
          .map((e) => AccountingClient.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      if (mounted) state = [];
    } finally {
      if (mounted) {
        _ref.read(accountingLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> reload() => _load();

  /// Publish add/edit changes only after the server confirms persistence.
  Future<void> _persist(AccountingClient client) async {
    if (_ref.read(isDemoProvider)) return;
    await _ref.read(accountingClientWriterProvider)(client);
  }

  Future<void> addClient(AccountingClient client) async {
    await _persist(client);
    if (!mounted) return;
    // A retry after a lost response uses the same id (server upsert).
    state = [...state.where((c) => c.id != client.id), client];
  }

  Future<void> updateClient(AccountingClient updated) async {
    await _persist(updated);
    if (!mounted) return;
    state = state.map((c) => c.id == updated.id ? updated : c).toList();
  }

  Future<void> removeClient(String id) async {
    state = state.where((c) => c.id != id).toList();
    if (_ref.read(isDemoProvider)) return;
    await ApiClient.delete('/accounting/clients/$id');
  }

  Future<void> toggleDoc(String clientId, String docId) async {
    AccountingClient? changed;
    state = state.map((c) {
      if (c.id != clientId) return c;
      final newChecklist = c.checklist.map((d) {
        if (d.id != docId) return d;
        return d.copyWith(received: !d.received);
      }).toList();
      return changed = c.copyWith(checklist: newChecklist);
    }).toList();
    if (changed != null) await _persist(changed!);
  }

  Future<void> toggleFee(String clientId, {DateTime? month}) async {
    final period = month ?? DateTime.now();
    final key = feeMonthKey(period);
    if (!_pendingFees.add('$clientId/$key')) return;
    try {
      final client = state.firstWhere((c) => c.id == clientId);
      final received = !client.feeReceivedFor(period);
      List<FeePayment> payments;
      if (_ref.read(isDemoProvider)) {
        final previous =
            client.feePayments.where((p) => p.month == key).firstOrNull;
        payments = [
          ...client.feePayments.where((p) => p.month != key),
          FeePayment(
              month: key,
              amount: previous?.amount ?? client.monthlyFee,
              received: received)
        ];
      } else {
        final result = await ApiClient.put(
            '/accounting/clients/${Uri.encodeComponent(clientId)}/fees/$key',
            {'received': received});
        payments = (result['payments'] as List)
            .map((p) => FeePayment.fromJson(p as Map))
            .toList();
      }
      if (mounted) {
        state = state
            .map(
                (c) => c.id == clientId ? c.copyWith(feePayments: payments) : c)
            .toList();
      }
    } finally {
      _pendingFees.remove('$clientId/$key');
    }
  }

  AccountingClient createEmpty() => AccountingClient(
        id: _uuid.v4(),
        name: '',
        binOrIin: '',
        entityType: ClientEntityType.ip,
        regime: ClientTaxRegime.simplified910,
        checklist: _defaultChecklist(ClientTaxRegime.simplified910),
      );
}

List<DocChecklistItem> _defaultChecklist(ClientTaxRegime regime) {
  final now = DateTime.now();
  final label = '${_monthName(now.month)} ${now.year}';
  return switch (regime) {
    ClientTaxRegime.simplified910 || ClientTaxRegime.patent => [
        DocChecklistItem(id: _uuid.v4(), label: 'Банковская выписка за $label'),
        DocChecklistItem(id: _uuid.v4(), label: 'Реестр доходов за $label'),
      ],
    ClientTaxRegime.esp => [
        DocChecklistItem(id: _uuid.v4(), label: 'Выписка по счёту за $label'),
      ],
    ClientTaxRegime.our => [
        DocChecklistItem(id: _uuid.v4(), label: 'Банковская выписка за $label'),
        DocChecklistItem(id: _uuid.v4(), label: 'Авансовые отчёты за $label'),
        DocChecklistItem(id: _uuid.v4(), label: 'Акты выполненных работ'),
        DocChecklistItem(id: _uuid.v4(), label: 'Счёт-фактуры за $label'),
      ],
  };
}

final accountingProvider =
    StateNotifierProvider<AccountingNotifier, List<AccountingClient>>((ref) {
  ref.watch(authProvider);
  return AccountingNotifier(ref);
});

// Derived: all deadlines for next 60 days across all clients
final allUpcomingDeadlinesProvider = Provider<List<ClientDeadline>>((ref) {
  final clients = ref.watch(accountingProvider);
  final now = DateTime.now();
  final all =
      clients.expand((c) => generateClientDeadlines(c, now, 60)).toList();
  all.sort((a, b) => a.date.compareTo(b.date));
  return all;
});

// Derived: urgent count (deadline <= 3 days)
final urgentCountProvider = Provider<int>((ref) {
  return ref.watch(accountingProvider).where((c) {
    final d = nearestDeadline(c);
    return d != null && d.daysLeft <= 3;
  }).length;
});

// Derived: clients awaiting docs
final awaitingDocsCountProvider = Provider<int>((ref) {
  return ref.watch(accountingProvider).where((c) => c.missingDocs > 0).length;
});

// Derived: total monthly fee + received
final totalFeeProvider = Provider<({double total, double received})>((ref) {
  final clients = ref.watch(accountingProvider);
  final total = clients.fold(0.0, (s, c) => s + c.monthlyFee);
  final received = clients.fold(0.0, (s, c) => s + c.receivedFeeThisMonth);
  return (total: total, received: received);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

String _monthName(int month) => const [
      '',
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек'
    ][month];

DateTime _addMonths(DateTime base, int offset) {
  var m = base.month + offset;
  var y = base.year;
  while (m > 12) {
    m -= 12;
    y++;
  }
  while (m < 1) {
    m += 12;
    y--;
  }
  return DateTime(y, m, 1);
}
