import 'package:clarimoney_backend/src/comparison_calculation.dart';
import 'package:postgres/postgres.dart';

num? _net(num? income, num? expense) =>
    income == null || expense == null ? null : income - expense;

String comparisonIso(DateTime value) =>
    '${value.toUtc().toIso8601String().split('.').first}.000Z';

Map<String, dynamic> _withSides(
  Map<String, dynamic> value,
  num? current,
  num? previous,
) => {...value, 'current': current, 'previous': previous};

Map<String, dynamic> comparisonPeriods({
  required DateTime currentStart,
  required DateTime currentEnd,
  required ComparisonPeriod previous,
}) => {
  'current': {
    'start': comparisonIso(currentStart),
    'end': comparisonIso(currentEnd),
  },
  'previous': {
    'start': comparisonIso(previous.start),
    'end': comparisonIso(previous.end),
  },
};

Future<Map<String, dynamic>> fetchComparison({
  required Pool<dynamic> pool,
  required String userId,
  required String period,
  String? categoryId,
}) async {
  final now = DateTime.now().toUtc();
  final currentStart = period == 'previous_month'
      ? DateTime.utc(now.year, now.month - 1)
      : DateTime.utc(now.year, now.month);
  final currentEnd = period == 'previous_month'
      ? DateTime.utc(now.year, now.month)
      : DateTime.utc(now.year, now.month + 1);
  final previous = deriveComparisonPeriod(start: currentStart, end: currentEnd);

  String? categoryName;
  if (categoryId != null) {
    final category = await pool.execute(
      Sql.named('''
        SELECT name FROM categories
        WHERE id = @categoryId AND (user_id = @userId OR user_id IS NULL)
      '''),
      parameters: {'categoryId': categoryId, 'userId': userId},
    );
    if (category.isEmpty) throw StateError('category not found');
    categoryName = category.first.first as String;
  }

  final parameters = {
    'userId': userId,
    'currentStart': currentStart,
    'currentEnd': currentEnd,
    'previousStart': previous.start,
    'previousEnd': previous.end,
    'categoryId': categoryId,
  };
  final totals = await pool.execute(
    Sql.named('''
      SELECT
        SUM(t.amount) FILTER (WHERE t.type = 'income' AND t.date >= @currentStart AND t.date < @currentEnd),
        SUM(t.amount) FILTER (WHERE t.type = 'income' AND t.date >= @previousStart AND t.date < @previousEnd),
        SUM(t.amount) FILTER (WHERE t.type = 'expense' AND t.date >= @currentStart AND t.date < @currentEnd),
        SUM(t.amount) FILTER (WHERE t.type = 'expense' AND t.date >= @previousStart AND t.date < @previousEnd)
      FROM transactions t
      WHERE t.user_id = @userId
        AND ((t.date >= @currentStart AND t.date < @currentEnd)
          OR (t.date >= @previousStart AND t.date < @previousEnd))
        AND (@categoryId IS NULL OR t.category_id = @categoryId)
    '''),
    parameters: parameters,
  );
  final total = totals.first;
  final categories = await pool.execute(
    Sql.named('''
      SELECT c.id, c.name,
        SUM(t.amount) FILTER (WHERE t.date >= @currentStart AND t.date < @currentEnd),
        SUM(t.amount) FILTER (WHERE t.date >= @previousStart AND t.date < @previousEnd)
      FROM categories c
      LEFT JOIN transactions t ON t.category_id = c.id
        AND t.user_id = @userId
        AND ((t.date >= @currentStart AND t.date < @currentEnd)
          OR (t.date >= @previousStart AND t.date < @previousEnd))
      WHERE (c.user_id = @userId OR c.user_id IS NULL)
        AND (@categoryId IS NULL OR c.id = @categoryId)
      GROUP BY c.id, c.name
      ORDER BY c.id ASC
    '''),
    parameters: parameters,
  );

  final currentCategories = <String, CategoryTotal>{};
  final previousCategories = <String, CategoryTotal>{};
  for (final row in categories) {
    final id = row[0].toString();
    final name = row[1] as String;
    currentCategories[id] = CategoryTotal(name: name, value: row[2] as num?);
    previousCategories[id] = CategoryTotal(name: name, value: row[3] as num?);
  }
  final result = buildComparison(
    current: PeriodTotals(
      income: total[0] as num?,
      expense: total[2] as num?,
      categories: currentCategories,
    ),
    previous: PeriodTotals(
      income: total[1] as num?,
      expense: total[3] as num?,
      categories: previousCategories,
    ),
  );
  final periods = comparisonPeriods(
    currentStart: currentStart,
    currentEnd: currentEnd,
    previous: previous,
  );
  if (categoryId != null) {
    final category =
        result.categories[categoryId] ??
        {
          'category_id': categoryId,
          'name': categoryName,
          ...compareValue(current: null, previous: null),
        };
    final currentCategory = currentCategories[categoryId];
    final previousCategory = previousCategories[categoryId];
    return {
      'period': period,
      'periods': periods,
      'category_id': category['category_id'],
      'name': category['name'],
      'current': currentCategory?.value,
      'previous': previousCategory?.value,
      'absolute_change': category['absolute_change'],
      'percentage_change': category['percentage_change'],
    };
  }
  return {
    'period': period,
    'periods': periods,
    'income': _withSides(result.income, total[0] as num?, total[1] as num?),
    'expense': _withSides(result.expense, total[2] as num?, total[3] as num?),
    'net_cash_flow': {
      ...result.netCashFlow,
      'current': _net(total[0] as num?, total[2] as num?),
      'previous': _net(total[1] as num?, total[3] as num?),
    },
    'categories': {
      for (final entry in result.categories.entries)
        entry.key: {
          ...entry.value,
          'current': currentCategories[entry.key]?.value,
          'previous': previousCategories[entry.key]?.value,
        },
    },
    'drivers': result.drivers
        .map(
          (driver) => {
            ...driver,
            'current': currentCategories[driver['category_id']]?.value,
            'previous': previousCategories[driver['category_id']]?.value,
          },
        )
        .toList(),
  };
}
