import 'package:clarimoney_backend/src/comparison_calculation.dart';
import 'package:postgres/postgres.dart';

String comparisonIso(DateTime value) =>
    '${value.toUtc().toIso8601String().split('.').first}.000Z';

Future<Map<String, dynamic>> fetchComparison({
  required Pool<dynamic> pool,
  required String userId,
  required String period,
  String? categoryId,
}) async {
  if (categoryId != null) {
    final owned = await pool.execute(
      Sql.named(
        'SELECT id FROM categories WHERE id = @categoryId AND user_id = @userId',
      ),
      parameters: {'categoryId': categoryId, 'userId': userId},
    );
    if (owned.isEmpty) throw StateError('category not found');
  }
  final now = DateTime.now().toUtc();
  final currentStart = period == 'previous_month'
      ? DateTime.utc(now.year, now.month - 1)
      : DateTime.utc(now.year, now.month);
  final currentEnd = period == 'previous_month'
      ? DateTime.utc(now.year, now.month)
      : DateTime.utc(now.year, now.month + 1);
  final previous = deriveComparisonPeriod(start: currentStart, end: currentEnd);
  final rows = await pool.execute(
    Sql.named('''
    SELECT t.category_id, c.name, t.type, t.amount, t.date
    FROM transactions t JOIN categories c ON c.id = t.category_id
    WHERE t.user_id = @userId AND (
      (t.date >= @currentStart AND t.date < @currentEnd) OR
      (t.date >= @previousStart AND t.date < @previousEnd)
    ) AND (@categoryId IS NULL OR t.category_id = @categoryId)
    ORDER BY t.category_id ASC, t.date ASC, t.id ASC
  '''),
    parameters: {
      'userId': userId,
      'currentStart': currentStart,
      'currentEnd': currentEnd,
      'previousStart': previous.start,
      'previousEnd': previous.end,
      'categoryId': categoryId,
    },
  );
  final currentRows = <ComparisonTransaction>[];
  final previousRows = <ComparisonTransaction>[];
  for (final row in rows) {
    final transaction = ComparisonTransaction(
      categoryId: row[0].toString(),
      categoryName: row[1] as String,
      type: row[2] as String,
      amount: row[3] as num,
    );
    final date = (row[4] as DateTime).toUtc();
    if (!date.isBefore(currentStart) && date.isBefore(currentEnd)) {
      currentRows.add(transaction);
    } else if (!date.isBefore(previous.start) && date.isBefore(previous.end)) {
      previousRows.add(transaction);
    }
  }
  final result = buildComparison(
    current: aggregatePeriod(currentRows),
    previous: aggregatePeriod(previousRows),
  );
  final periods = {
    'current': {
      'start': comparisonIso(currentStart),
      'end': comparisonIso(currentEnd),
    },
    'previous': {
      'start': comparisonIso(previous.start),
      'end': comparisonIso(previous.end),
    },
  };
  final data = <String, dynamic>{
    'period': period,
    'periods': periods,
    'income': result.income,
    'expense': result.expense,
    'net_cash_flow': result.netCashFlow,
    'categories': result.categories,
    'drivers': result.drivers,
  };
  if (categoryId != null) {
    final category = result.categories[categoryId];
    if (category == null) throw StateError('category not found');
    return {...data, ...category};
  }
  return data;
}
