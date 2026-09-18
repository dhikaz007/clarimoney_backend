import 'package:test/test.dart';

import 'package:clarimoney_backend/src/summary_calculation.dart';

void main() {
  test('empty period', () {
    final data = buildSummaryData(
      income: null,
      expense: null,
      incomeCount: 0,
      items: [],
    );
    expect(data['total_income'], 0);
    expect(data['total_expense'], 0);
    expect(data['net_cash_flow_available'], isFalse);
    expect(data['net_cash_flow'], isNull);
    expect(data['largest_category'], isNull);
  });

  test('expense-only period', () {
    final items = <Map<String, dynamic>>[
      {'total': 10.25},
    ];
    final data = buildSummaryData(
      income: null,
      expense: 10.25,
      incomeCount: 0,
      items: items,
    );
    expect(data['net_cash_flow_available'], isFalse);
    expect(data['net_cash_flow'], isNull);
    expect(items.first['percentage'], 100);
  });

  test('income-only and full periods preserve precision', () {
    final incomeOnly = buildSummaryData(
      income: 100.10,
      expense: null,
      incomeCount: 1,
      items: [],
    );
    expect(incomeOnly['net_cash_flow'], 100.10);

    final full = buildSummaryData(
      income: 100.10,
      expense: 0.10,
      incomeCount: 1,
      items: [
        {'total': 0.10},
      ],
    );
    expect(full['net_cash_flow'], 100.0);
    expect(full['total_income'], 100.10);
    expect(full['total_expense'], 0.10);
  });

  test('large decimal values stay exact in JSON shape', () {
    final data = buildSummaryData(
      income: '9007199254740991.99',
      expense: '0.01',
      incomeCount: 1,
      items: [
        {'total': '0.01'},
      ],
      netCashFlow: '9007199254740991.98',
    );
    expect(data['total_income'], '9007199254740991.99');
    expect(data['total_expense'], 0.01);
    expect(data['net_cash_flow'], '9007199254740991.98');
  });
}
