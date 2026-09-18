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
      'percentage_change': null,
    });
    expect(compareValue(current: null, previous: 10), {
      'value': null,
      'absolute_change': null,
      'percentage_change': null,
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
      'absolute_change': null,
      'percentage_change': null,
    });
  });

  test('normalizes local and DST inputs before deriving January rollover', () {
    final period = deriveComparisonPeriod(
      start: DateTime.parse('2026-03-01T00:00:00-05:00'),
      end: DateTime.parse('2026-03-16T00:00:00-04:00'),
    );

    expect(period.start, DateTime.utc(2026, 2, 1));
    expect(period.end, DateTime.utc(2026, 2, 16));
    expect(period.start.isUtc, isTrue);
    expect(period.end.isUtc, isTrue);
  });

  test('derives January prior month in previous year', () {
    final period = deriveComparisonPeriod(
      start: DateTime.utc(2026, 1, 1),
      end: DateTime.utc(2026, 2, 1),
    );

    expect(period.start, DateTime.utc(2025, 12, 1));
    expect(period.end, DateTime.utc(2026, 1, 1));
  });

  test('handles short previous month without zero-length period', () {
    final period = deriveComparisonPeriod(
      start: DateTime.utc(2026, 3, 31),
      end: DateTime.utc(2026, 4, 30),
    );

    expect(period.start, DateTime.utc(2026, 2, 28));
    expect(period.end.isAfter(period.start), isTrue);
    expect(period.end, DateTime.utc(2026, 3, 30));
  });

  test('preserves equivalent elapsed range across month boundary', () {
    final period = deriveComparisonPeriod(
      start: DateTime.utc(2026, 1, 20),
      end: DateTime.utc(2026, 2, 10),
    );

    expect(period.start, DateTime.utc(2025, 12, 20));
    expect(period.end, DateTime.utc(2026, 1, 10));
    expect(period.end.difference(period.start), const Duration(days: 21));
  });

  test('rejects non-finite comparison values', () {
    expect(
      () => compareValue(current: double.nan, previous: 1),
      throwsArgumentError,
    );
    expect(
      () => compareValue(current: double.infinity, previous: 1),
      throwsArgumentError,
    );
    expect(
      () => compareValue(current: 1, previous: double.negativeInfinity),
      throwsArgumentError,
    );
  });

  test('uses consistent null keys for unavailable comparison values', () {
    expect(compareValue(current: null, previous: 1), {
      'value': null,
      'absolute_change': null,
      'percentage_change': null,
    });
    expect(compareValue(current: 1, previous: 0), {
      'value': 1,
      'absolute_change': 1,
      'percentage_change': null,
    });
  });

  test(
    'excludes zero changes from drivers and ignores invalid transaction types',
    () {
      final current = aggregatePeriod([
        const ComparisonTransaction(
          categoryId: 'same',
          categoryName: 'Same',
          type: 'expense',
          amount: 10,
        ),
        const ComparisonTransaction(
          categoryId: 'invalid',
          categoryName: 'Invalid',
          type: 'transfer',
          amount: 100,
        ),
      ]);
      final previous = aggregatePeriod([
        const ComparisonTransaction(
          categoryId: 'same',
          categoryName: 'Same',
          type: 'expense',
          amount: 10,
        ),
      ]);

      expect(current.expense, 10);
      expect(current.income, isNull);
      expect(
        buildComparison(current: current, previous: previous).drivers,
        isEmpty,
      );
    },
  );

  test('preserves decimal raw precision without percentage rounding', () {
    final result = compareValue(current: 1.005, previous: 1.0);

    expect(result['absolute_change'], closeTo(0.005, 0.000000001));
    expect(result['percentage_change'], closeTo(0.5, 0.000000001));
  });
}
