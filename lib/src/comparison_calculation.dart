class ComparisonPeriod {
  const ComparisonPeriod(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

class ComparisonTransaction {
  const ComparisonTransaction({
    required this.categoryId,
    required this.categoryName,
    required this.type,
    required this.amount,
  });

  final String categoryId;
  final String categoryName;
  final String type;
  final num amount;
}

class PeriodTotals {
  const PeriodTotals({
    required this.income,
    required this.expense,
    required this.categories,
  });

  final num? income;
  final num? expense;
  final Map<String, CategoryTotal> categories;
}

class CategoryTotal {
  const CategoryTotal({required this.name, required this.value});

  final String name;
  final num? value;
}

class ComparisonResult {
  const ComparisonResult({
    required this.income,
    required this.expense,
    required this.netCashFlow,
    required this.categories,
    required this.drivers,
  });

  final Map<String, dynamic> income;
  final Map<String, dynamic> expense;
  final Map<String, dynamic> netCashFlow;
  final Map<String, Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> drivers;
}

ComparisonPeriod deriveComparisonPeriod({
  required DateTime start,
  required DateTime end,
}) {
  final startUtc = start.toUtc();
  final endUtc = end.toUtc();
  final currentStart = DateTime.utc(
    startUtc.year,
    startUtc.month,
    startUtc.day,
  );
  final currentEnd = DateTime.utc(endUtc.year, endUtc.month, endUtc.day);
  if (!currentEnd.isAfter(currentStart)) {
    throw ArgumentError('comparison period must be non-empty');
  }
  final days = currentEnd.difference(currentStart).inDays;
  final previousYear = currentStart.month == 1
      ? currentStart.year - 1
      : currentStart.year;
  final previousMonth = currentStart.month == 1 ? 12 : currentStart.month - 1;
  final previousMonthDays = DateTime.utc(
    currentStart.year,
    currentStart.month,
    0,
  ).day;
  final previousStart = DateTime.utc(
    previousYear,
    previousMonth,
    currentStart.day.clamp(1, previousMonthDays),
  );
  final previousEnd = currentStart.day == 1 && currentEnd.day == 1
      ? DateTime.utc(previousStart.year, previousStart.month + 1)
      : previousStart.add(Duration(days: days));
  return ComparisonPeriod(previousStart, previousEnd);
}

Map<String, dynamic> compareValue({
  required num? current,
  required num? previous,
}) {
  // Precision policy: preserve raw numeric arithmetic; do not round values or percentages.
  for (final value in [current, previous]) {
    if (value != null && !value.isFinite) {
      throw ArgumentError('comparison values must be finite');
    }
  }
  final result = <String, dynamic>{
    'value': current,
    'absolute_change': null,
    'percentage_change': null,
  };
  if (current == null || previous == null) {
    return result;
  }
  final change = current - previous;
  if (!change.isFinite) return result;
  result['absolute_change'] = change;
  if (previous != 0) {
    final percentage = change / previous * 100;
    if (percentage.isFinite) result['percentage_change'] = percentage;
  }
  return result;
}

PeriodTotals aggregatePeriod(Iterable<ComparisonTransaction> transactions) {
  num? income;
  num? expense;
  final categories = <String, CategoryTotal>{};
  for (final transaction in transactions) {
    if (!transaction.amount.isFinite) {
      throw ArgumentError('transaction amounts must be finite');
    }
    if (transaction.type == 'income') {
      final sum = income == null
          ? transaction.amount
          : income + transaction.amount;
      income = sum.isFinite ? sum : null;
    } else if (transaction.type == 'expense') {
      final sum = expense == null
          ? transaction.amount
          : expense + transaction.amount;
      expense = sum.isFinite ? sum : null;
    } else {
      continue;
    }
    final category = categories[transaction.categoryId];
    final sum = category?.value == null
        ? transaction.amount
        : category!.value! + transaction.amount;
    categories[transaction.categoryId] = CategoryTotal(
      name: transaction.categoryName,
      value: sum.isFinite ? sum : null,
    );
  }
  return PeriodTotals(income: income, expense: expense, categories: categories);
}

ComparisonResult buildComparison({
  required PeriodTotals current,
  required PeriodTotals previous,
}) {
  final categories = <String, Map<String, dynamic>>{};
  final ids = {...current.categories.keys, ...previous.categories.keys}.toList()
    ..sort();
  for (final id in ids) {
    final currentCategory = current.categories[id];
    final previousCategory = previous.categories[id];
    categories[id] = {
      'category_id': id,
      'name': currentCategory?.name ?? previousCategory!.name,
      ...compareValue(
        current: currentCategory?.value,
        previous: previousCategory?.value,
      ),
    };
  }

  final drivers =
      ids
          .map((id) {
            final item = categories[id]!;
            final currentValue = current.categories[id]?.value;
            final previousValue = previous.categories[id]?.value;
            final change = currentValue == null && previousValue != null
                ? -previousValue
                : currentValue != null && previousValue == null
                ? currentValue
                : (item['absolute_change'] as num?);
            return {
              ...item,
              'absolute_change': change,
              '_magnitude': change?.abs() ?? -1,
            };
          })
          .where((item) => item['_magnitude'] > 0)
          .toList()
        ..sort((a, b) {
          final magnitude = (b['_magnitude'] as num).compareTo(
            a['_magnitude'] as num,
          );
          return magnitude == 0
              ? (a['category_id'] as String).compareTo(
                  b['category_id'] as String,
                )
              : magnitude;
        });
  for (final driver in drivers) {
    driver.remove('_magnitude');
  }

  final netCurrent = _safeDifference(current.income, current.expense);
  final netPrevious = _safeDifference(previous.income, previous.expense);
  return ComparisonResult(
    income: compareValue(current: current.income, previous: previous.income),
    expense: compareValue(current: current.expense, previous: previous.expense),
    netCashFlow: {
      'available': netCurrent != null && netPrevious != null,
      ...compareValue(current: netCurrent, previous: netPrevious),
    },
    categories: categories,
    drivers: drivers.take(3).toList(),
  );
}

num? _safeDifference(num? left, num? right) {
  if (left == null || right == null) return null;
  final result = left - right;
  return result.isFinite ? result : null;
}
