import 'dart:async';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/summary_calculation.dart';

FutureOr<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  final userId = context.read<String>();
  final pool = context.read<Pool<dynamic>>();
  final period = context.request.uri.queryParameters['period'] ?? 'this_month';
  final now = DateTime.now().toUtc();
  final start = period == 'previous_month'
      ? DateTime.utc(now.year, now.month - 1)
      : DateTime.utc(now.year, now.month);
  final end = period == 'previous_month'
      ? DateTime.utc(now.year, now.month)
      : DateTime.utc(now.year, now.month + 1);

  if (period != 'this_month' && period != 'previous_month') {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'period must be this_month or previous_month',
    );
  }

  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT c.id, c.name, c.color, c.icon, SUM(t.amount) as total
        FROM transactions t
        JOIN categories c ON t.category_id = c.id
        WHERE t.user_id = @userId AND t.type = 'expense'
          AND t.date >= @start AND t.date < @end
        GROUP BY c.id
        ORDER BY total DESC, c.id ASC
      '''),
      parameters: {'userId': userId, 'start': start, 'end': end},
    );

    final items = <Map<String, dynamic>>[];

    for (final row in result) {
      final total = row[4] as num;
      items.add({
        'category_id': row[0],
        'name': row[1],
        'color': row[2],
        'icon': row[3],
        'total': total,
      });
    }

    final totals = await pool.execute(
      Sql.named('''
        SELECT
          SUM(t.amount) FILTER (WHERE t.type = 'income'),
          SUM(t.amount) FILTER (WHERE t.type = 'expense'),
          COUNT(*) FILTER (WHERE t.type = 'income'),
          COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'income'), 0)
            - COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'expense'), 0)
        FROM transactions t
        WHERE t.user_id = @userId AND t.date >= @start AND t.date < @end
      '''),
      parameters: {'userId': userId, 'start': start, 'end': end},
    );
    final totalRow = totals.first;
    final summaryData = buildSummaryData(
      income: totalRow[0] as num?,
      expense: totalRow[1] as num?,
      incomeCount: (totalRow[2] as int?) ?? 0,
      items: items,
      netCashFlow: totalRow[3] as num?,
    );

    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Summary fetched successfully',
      data: {...summaryData, 'period': period, 'summary': items},
    );
  } catch (e) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Failed to fetch summary',
    );
  }
}
