import 'dart:async';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:clarimoney_backend/src/api_response.dart';

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
      ? DateTime(now.year, now.month - 1).toUtc()
      : DateTime(now.year, now.month).toUtc();
  final end = period == 'previous_month'
      ? DateTime(now.year, now.month).toUtc()
      : DateTime(now.year, now.month + 1).toUtc();

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
        WHERE t.user_id = @userId AND t.date >= @start AND t.date < @end
        GROUP BY c.id
        ORDER BY total DESC
      '''),
      parameters: {'userId': userId, 'start': start, 'end': end},
    );

    double grandTotal = 0;
    final items = <Map<String, dynamic>>[];

    for (final row in result) {
      final total = (row[4] as num?)?.toDouble() ?? 0;
      grandTotal += total;
      items.add({
        'category_id': row[0],
        'name': row[1],
        'color': row[2],
        'icon': row[3],
        'total': total,
      });
    }

    for (final item in items) {
      final total = item['total'] as double;
      item['percentage'] = grandTotal > 0 ? total / grandTotal * 100 : 0;
    }

    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Summary fetched successfully',
      data: {
        'total_expense': grandTotal,
        'period': period,
        'summary': items,
        'largest_category': items.isNotEmpty ? items.first : null,
      },
    );
  } catch (e) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Failed to fetch summary',
    );
  }
}
