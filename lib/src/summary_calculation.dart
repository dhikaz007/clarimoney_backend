Map<String, dynamic> buildSummaryData({
  required num? income,
  required num? expense,
  required int incomeCount,
  required List<Map<String, dynamic>> items,
  num? netCashFlow,
}) {
  final totalIncome = income ?? 0;
  final totalExpense = expense ?? 0;
  for (final item in items) {
    final total = item['total'] as num;
    item['percentage'] = totalExpense == 0 ? 0 : total / totalExpense * 100;
  }
  final available = incomeCount > 0;
  return {
    'total_income': totalIncome,
    'total_expense': totalExpense,
    'net_cash_flow_available': available,
    'net_cash_flow': available
        ? (netCashFlow ?? totalIncome - totalExpense)
        : null,
    'largest_category': items.isEmpty ? null : items.first,
  };
}
