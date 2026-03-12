import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/accounting_client.dart';
import '../constants/kz_tax_constants.dart';

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
        DocChecklistItem(id: 'd1', label: 'Банковская выписка за $monthLabel', received: true),
        DocChecklistItem(id: 'd2', label: 'Реестр доходов за $monthLabel', received: false),
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
      feeReceivedThisMonth: true,
      checklist: [
        DocChecklistItem(id: 'd3', label: 'Банковская выписка за $monthLabel', received: true),
        DocChecklistItem(id: 'd4', label: 'Авансовые отчёты за $monthLabel', received: true),
        const DocChecklistItem(id: 'd5', label: 'Акты выполненных работ', received: true),
        DocChecklistItem(id: 'd6', label: 'Счёт-фактуры за $monthLabel', received: false),
      ],
    ),
    AccountingClient(
      id: 'demo-3',
      name: 'Сейткали Айгерим',
      binOrIin: '920615400218',
      entityType: ClientEntityType.ip,
      regime: ClientTaxRegime.esp,
      employees: [],
      monthlyFee: 8000,
      feeReceivedThisMonth: true,
      checklist: [
        DocChecklistItem(id: 'd7', label: 'Выписка по счёту за $monthLabel', received: false),
      ],
    ),
    AccountingClient(
      id: 'demo-4',
      name: 'Нурланов Дидар Маратович',
      binOrIin: '910922400312',
      entityType: ClientEntityType.ip,
      regime: ClientTaxRegime.patent,
      employees: [],
      monthlyFee: 10000,
      feeReceivedThisMonth: false,
      checklist: [
        DocChecklistItem(id: 'd8', label: 'Реестр доходов за $monthLabel', received: true),
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
      feeReceivedThisMonth: true,
      checklist: [
        DocChecklistItem(id: 'd9', label: 'Банковская выписка за $monthLabel', received: true),
        DocChecklistItem(id: 'd10', label: 'Реестр доходов за $monthLabel', received: true),
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
  final to = from.add(Duration(days: days));

  void add(String type, String label, DateTime date) {
    if (date.isAfter(from.subtract(const Duration(days: 1))) && date.isBefore(to)) {
      deadlines.add(ClientDeadline(
        clientId: client.id,
        clientName: client.name,
        type: type,
        label: label,
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
        add('social', 'Соцплатежи (ОПВ+СО+ВОСМС) · ${_monthName(month)}',
            DateTime(year, month, 25));

        // 910 форма — 15 февраля и 15 августа
        if (client.regime == ClientTaxRegime.simplified910) {
          add('910', '910 форма за I полугодие $year', DateTime(year, 2, 15));
          add('910', '910 форма за II полугодие $year', DateTime(year, 8, 15));
        }

      case ClientTaxRegime.esp:
        // ЕСП — до 25-го каждого месяца
        add('esp', 'ЕСП · ${_monthName(month)} $year', DateTime(year, month, 25));

      case ClientTaxRegime.our:
        // Зарплатные налоги — до 25-го
        add('payroll', 'ИПН/ОПВ/СО сотрудников · ${_monthName(month)}',
            DateTime(year, month, 25));

        // 200.00 — ежеквартально, 15-го следующего месяца
        // Q1→апр15, Q2→июл15, Q3→окт15, Q4→янв15
        for (final qMonth in [4, 7, 10, 1]) {
          final qYear = qMonth == 1 ? year + 1 : year;
          add('200', '200.00 за ${_quarterLabel(qMonth)} $year',
              DateTime(qYear, qMonth, 15));
        }

        // 700.00 КПН — 31 марта ежегодно
        add('700', 'Форма 700.00 (КПН) за $year', DateTime(year, 3, 31));
    }
  }

  // Убираем дубликаты по (type, date)
  final seen = <String>{};
  deadlines.retainWhere((d) => seen.add('${d.type}_${d.date.toIso8601String()}'));

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
  final mrp = KzTax.currentMrp;
  final mzp = KzTax.currentMzp;

  // ОПВ: 10% от зарплаты, max база = 50 МЗП (ст. 25 Закона о пенсионном обеспечении)
  final opvBase = salary.clamp(0, mzp * 50);
  final opv = opvBase * KzTax.employeeOpvRate;

  // ВОСМС (сотрудника): 2%, max база = 20 МЗП (ст. 28 Закона о ОСМС, ред. 2026)
  final vosmsSelfBase = salary.clamp(0, KzTax.employeeVosmsMaxBase);
  final vosmsSelf = vosmsSelfBase * KzTax.employeeVosmsRate;

  // ИПН: 10% от (зарплата - ОПВ - 14 МРП стандартный вычет) (ст. 353 НК РК)
  final standardDeduction = mrp * 14;
  final ipnBase = (salary - opv - standardDeduction).clamp(0, double.infinity);
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

class AccountingNotifier extends StateNotifier<List<AccountingClient>> {
  AccountingNotifier() : super(_demoClients());

  void addClient(AccountingClient client) {
    state = [...state, client];
  }

  void updateClient(AccountingClient updated) {
    state = state.map((c) => c.id == updated.id ? updated : c).toList();
  }

  void removeClient(String id) {
    state = state.where((c) => c.id != id).toList();
  }

  void toggleDoc(String clientId, String docId) {
    state = state.map((c) {
      if (c.id != clientId) return c;
      final newChecklist = c.checklist.map((d) {
        if (d.id != docId) return d;
        return d.copyWith(received: !d.received);
      }).toList();
      return c.copyWith(checklist: newChecklist);
    }).toList();
  }

  void toggleFee(String clientId) {
    state = state.map((c) {
      if (c.id != clientId) return c;
      return c.copyWith(feeReceivedThisMonth: !c.feeReceivedThisMonth);
    }).toList();
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
    StateNotifierProvider<AccountingNotifier, List<AccountingClient>>(
        (ref) => AccountingNotifier());

// Derived: all deadlines for next 60 days across all clients
final allUpcomingDeadlinesProvider = Provider<List<ClientDeadline>>((ref) {
  final clients = ref.watch(accountingProvider);
  final now = DateTime.now();
  final all = clients.expand((c) => generateClientDeadlines(c, now, 60)).toList();
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
  final received =
      clients.where((c) => c.feeReceivedThisMonth).fold(0.0, (s, c) => s + c.monthlyFee);
  return (total: total, received: received);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

String _monthName(int month) => const [
      '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ][month];

String _quarterLabel(int firstMonth) => switch (firstMonth) {
      4 => 'I кв.',
      7 => 'II кв.',
      10 => 'III кв.',
      _ => 'IV кв.',
    };

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
