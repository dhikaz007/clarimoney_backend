import 'exact_decimal.dart';

Map<String, dynamic> buildSummaryData({
  required Object? income,
  required Object? expense,
  required int incomeCount,
  required List<Map<String, dynamic>> items,
  Object? netCashFlow,
}) {
  final totalIncome = income == null
      ? ExactDecimal.parse(0)
      : ExactDecimal.parse(income);
  final totalExpense = expense == null
      ? ExactDecimal.parse(0)
      : ExactDecimal.parse(expense);
  for (final item in items) {
    final total = ExactDecimal.parse(item['total']);
    item['total'] = total.jsonValue;
    item['percentage'] = totalExpense.isZero
        ? 0
        : total.divide(totalExpense).multiplyInteger(100).jsonValue;
  }
  final available = incomeCount > 0;
  return {
    'total_income': totalIncome.jsonValue,
    'total_expense': totalExpense.jsonValue,
    'net_cash_flow_available': available,
    'net_cash_flow': available
        ? exactJsonDecimal(netCashFlow ?? (totalIncome - totalExpense))
        : null,
    'largest_category': items.isEmpty ? null : items.first,
  };
}
