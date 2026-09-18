import 'package:flutter_test/flutter_test.dart';
import 'package:esep/core/models/accounting_client.dart';
import 'package:esep/core/providers/accounting_provider.dart';

void main() {
  const company = AccountingClient(
      id: 'c',
      name: 'Company',
      binOrIin: '123456789012',
      entityType: ClientEntityType.too,
      regime: ClientTaxRegime.simplified910);
  test(
      '910 reports previous H2 in February and current H1 in August, weekends moved',
      () {
    final forms = generateClientDeadlines(company, DateTime(2026), 366)
        .where((d) => d.type == '910')
        .toList();
    expect(forms.map((d) => d.date),
        [DateTime(2026, 2, 16), DateTime(2026, 8, 17)]);
    expect(forms[0].label, contains('II полугодие 2025'));
    expect(forms[1].label, contains('I полугодие 2026'));
  });
  test('200 quarters and years with second-month deadlines', () {
    final forms = generateClientDeadlines(
            company.copyWith(regime: ClientTaxRegime.our), DateTime(2026), 365)
        .where((d) => d.type == '200')
        .toList();
    expect(forms.map((d) => d.date), [
      DateTime(2026, 2, 16),
      DateTime(2026, 5, 15),
      DateTime(2026, 8, 17),
      DateTime(2026, 11, 16)
    ]);
    expect(forms.first.label, contains('4 кв. 2025'));
    expect(forms.last.label, contains('3 кв. 2026'));
  });
  test('holiday transfer and previous payment month; no duplicates', () {
    final dates = generateClientDeadlines(company, DateTime(2026, 3, 1), 31);
    final social = dates.singleWhere((d) => d.type == 'social');
    expect(social.date, DateTime(2026, 3, 26));
    expect(social.label, contains('фев 2026'));
    expect(
        generateClientDeadlines(
            company.copyWith(isActive: false), DateTime(2026), 365),
        isEmpty);
  });
  test('due today included at 23h, no yesterday; future calendar flagged', () {
    final dates =
        generateClientDeadlines(company, DateTime(2026, 8, 17, 23), 1);
    expect(dates.single.date, DateTime(2026, 8, 17));
    final future = generateClientDeadlines(company, DateTime(2027, 2, 1), 28)
        .firstWhere((d) => d.type == '910');
    expect(future.label, contains('II полугодие 2026'));
    expect(future.label, contains('уточните календарь'));
  });
  test('legacy fee is not assigned to any month; amounts survive fee change',
      () {
    final paid = company
        .copyWith(monthlyFee: 20000, feeReceivedThisMonth: true, feePayments: [
      const FeePayment(month: '2026-08', amount: 10000, received: true),
      const FeePayment(month: '2026-09', amount: 15000, received: false),
    ]);
    expect(paid.feeReceivedFor(DateTime(2026, 8)), isTrue);
    expect(paid.feeReceivedFor(DateTime(2026, 9)), isFalse);
    expect(paid.feeReceivedFor(DateTime(2027, 8)), isFalse);
    expect(paid.copyWith(name: 'Changed').feePayments.first.amount, 10000);
    expect(paid.legacyFeeReceived, isTrue);
  });
}
