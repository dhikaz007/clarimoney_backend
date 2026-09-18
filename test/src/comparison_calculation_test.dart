import 'package:test/test.dart';

import 'package:clarimoney_backend/src/comparison_calculation.dart';

void main() {
  test('derives previous full month', () {
    final period = deriveComparisonPeriod(
      start: DateTime.utc(2026, 9, 1),
      end: DateTime.utc(2026, 10, 1),
    );

    expect(period.start, DateTime.utc(2026, 8, 1));
    expect(period.end, DateTime.utc(2026, 9, 1));
  });

  test('derives equivalent partial month without crossing month end', () {
    final period = deriveComparisonPeriod(
      start: DateTime.utc(2026, 9, 1),
      end: DateTime.utc(2026, 9, 16),
    );

    expect(period.start, DateTime.utc(2026, 8, 1));
    expect(period.end, DateTime.utc(2026, 8, 16));
  });

  test('keeps zero and missing distinct and omits unsafe percentages', () {
    expect(compareValue(current: 0, previous: 10), {
      'value': 0,
      'absolute_change': -10,
      'percentage_change': -100,
    });
    expect(compareValue(current: 10, previous: 0), {
      'value': 10,
      'absolute_change': 10,
    });
    expect(compareValue(current: null, previous: 10), {
      'absolute_change': null,
    });
  });

  test('compares sign transitions using signed absolute change', () {
    expect(compareValue(current: -5, previous: 5), {
      'value': -5,
      'absolute_change': -10,
      'percentage_change': -200,
    });
  });

  test(
    'aggregates categories by persistent identity and ranks three drivers',
    () {
      final current = aggregatePeriod([
        ComparisonTransaction(
          categoryId: 'a',
          categoryName: 'Renamed',
          type: 'expense',
          amount: 80,
        ),
        ComparisonTransaction(
          categoryId: 'b',
          categoryName: 'B',
          type: 'expense',
          amount: 30,
        ),
        ComparisonTransaction(
          categoryId: 'c',
          categoryName: 'Archived',
          type: 'expense',
          amount: 20,
        ),
      ]);
      final previous = aggregatePeriod([
        ComparisonTransaction(
          categoryId: 'a',
          categoryName: 'Old name',
          type: 'expense',
          amount: 10,
        ),
        ComparisonTransaction(
          categoryId: 'b',
          categoryName: 'B',
          type: 'expense',
          amount: 5,
        ),
        ComparisonTransaction(
          categoryId: 'c',
          categoryName: 'Archived',
          type: 'expense',
          amount: 1,
        ),
        ComparisonTransaction(
          categoryId: 'd',
          categoryName: 'Removed',
          type: 'expense',
          amount: 100,
        ),
      ]);
      final result = buildComparison(current: current, previous: previous);

      expect(result.categories['a']?['value'], 80);
      expect(result.categories['a']?['absolute_change'], 70);
      expect(result.categories['a']?['name'], 'Renamed');
      expect(result.drivers.map((driver) => driver['category_id']), [
        'd',
        'a',
        'b',
      ]);
      expect(result.drivers, hasLength(3));
    },
  );

  test('net cash flow is unavailable when either period lacks income', () {
    final current = aggregatePeriod([
      ComparisonTransaction(
        categoryId: 'a',
        categoryName: 'Salary',
        type: 'income',
        amount: 100,
      ),
    ]);
    final previous = aggregatePeriod([
      ComparisonTransaction(
        categoryId: 'b',
        categoryName: 'Food',
        type: 'expense',
        amount: 20,
      ),
    ]);

    expect(buildComparison(current: current, previous: previous).netCashFlow, {
      'available': false,
      'value': null,
    });
  });
}
