import 'dart:async';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';
import 'package:clarimoney_backend/src/api_response.dart';

FutureOr<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  final userId = context.read<String>();
  final pool = context.read<Pool<dynamic>>();

  if (method == HttpMethod.get) {
    try {
      final query = context.request.uri.queryParameters;
      final page = int.tryParse(query['page'] ?? '') ?? 1;
      final limit = int.tryParse(query['limit'] ?? '') ?? 10;

      if (page < 1 || limit < 1 || limit > 100) {
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'page must be >= 1 and limit must be between 1 and 100',
        );
      }

      final type = query['type'];
      final period = query['period'];
      final categoryId = query['category_id'];
      final search = query['search']?.trim();
      if (type != null &&
          type != 'all' &&
          type != 'income' &&
          type != 'expense') {
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'Invalid type',
        );
      }
      if (period != null &&
          period != 'this_month' &&
          period != 'previous_month') {
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'Invalid period',
        );
      }
      final conditions = <String>['t.user_id = @userId'];
      final parameters = <String, Object?>{
        'userId': userId,
        'limit': limit,
        'offset': (page - 1) * limit,
      };
      if (type != null && type != 'all') {
        conditions.add('t.type = @type');
        parameters['type'] = type;
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        conditions.add('t.category_id = @categoryId');
        parameters['categoryId'] = categoryId;
      }
      if (search != null && search.isNotEmpty) {
        conditions.add(
          '(lower(t.note) LIKE lower(@search) OR lower(c.name) LIKE lower(@search))',
        );
        parameters['search'] = '%$search%';
      }
      if (period != null) {
        final now = DateTime.now().toUtc();
        final start = period == 'this_month'
            ? DateTime.utc(now.year, now.month)
            : DateTime.utc(now.year, now.month - 1);
        final end = period == 'this_month'
            ? DateTime.utc(now.year, now.month + 1)
            : DateTime.utc(now.year, now.month);
        conditions.add('t.date >= @start AND t.date < @end');
        parameters['start'] = start;
        parameters['end'] = end;
      }
      final where = conditions.join(' AND ');
      final offset = (page - 1) * limit;
      final countResult = await pool.execute(
        Sql.named(
          'SELECT COUNT(*) FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE $where',
        ),
        parameters: parameters,
      );
      final total = (countResult.first.first as int?) ?? 0;

      final result = await pool.execute(
        Sql.named('''
          SELECT t.id, t.type, t.category_id, t.amount, t.date, t.note, t.created_at, c.name, c.color, c.icon
          FROM transactions t
          LEFT JOIN categories c ON t.category_id = c.id
          WHERE $where
          ORDER BY t.date DESC, t.created_at DESC, t.id DESC
          LIMIT @limit OFFSET @offset
        '''),
        parameters: parameters,
      );

      final transactions = result.map((row) {
        return {
          'id': row[0],
          'type': row[1],
          'category_id': row[2],
          'amount': row[3],
          'date': _iso(row[4]),
          'note': row[5],
          'created_at': _iso(row[6]),
          'category': {'name': row[7], 'color': row[8], 'icon': row[9]},
        };
      }).toList();

      return apiResponse(
        statusCode: HttpStatus.ok,
        message: 'Transactions fetched successfully',
        data: transactions,
        meta: {
          'page': page,
          'limit': limit,
          'total': total,
          'total_pages': total == 0 ? 0 : (total / limit).ceil(),
          'has_next': offset + transactions.length < total,
        },
      );
    } catch (e) {
      return apiResponse(
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to fetch transactions',
      );
    }
  }

  if (method == HttpMethod.post) {
    try {
      final body = await context.request.json() as Map<String, dynamic>;
      final categoryId = body['category_id'] as String?;
      final type = (body['type'] as String?) ?? 'expense';
      final amount = body['amount'] as num?;
      final dateRaw = body['date'] as String?;

      if (!_validAmount(amount) ||
          categoryId == null ||
          dateRaw == null ||
          (type != 'income' && type != 'expense')) {
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'category_id, amount, and date required',
        );
      }

      final date = _parseIso(dateRaw);
      if (date == null) {
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'Invalid date format',
        );
      }

      final category = await pool.execute(
        Sql.named('''
           SELECT id FROM categories
           WHERE id = @categoryId AND (user_id = @userId OR user_id IS NULL)
             AND type = @type AND status = 'active'
        '''),
        parameters: {'categoryId': categoryId, 'userId': userId, 'type': type},
      );
      if (category.isEmpty) {
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'Invalid category',
        );
      }

      final id = const Uuid().v4();
      await pool.execute(
        Sql.named('''
           INSERT INTO transactions (id, user_id, type, category_id, amount, date, note)
           VALUES (@id, @userId, @type, @categoryId, @amount, @date, @note)
        '''),
        parameters: {
          'id': id,
          'userId': userId,
          'type': type,
          'categoryId': categoryId,
          'amount': amount,
          'date': date,
          'note': _note(body['note']),
        },
      );

      return apiResponse(
        statusCode: HttpStatus.created,
        message: 'Transaction created successfully',
        data: {'id': id},
      );
    } on FormatException {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Invalid request body',
      );
    } on ServerException catch (e) {
      if (e.code == '23514' || e.code == '23503')
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'Invalid transaction',
        );
      return apiResponse(
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to create transaction',
      );
    } catch (e) {
      return apiResponse(
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to create transaction',
      );
    }
  }

  return apiResponse(
    statusCode: HttpStatus.methodNotAllowed,
    message: 'Method not allowed',
  );
}

String? _note(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().length > 500) {
    throw const FormatException('Invalid note');
  }
  return value.trim();
}

bool _validAmount(num? value) =>
    value != null &&
    value > 0 &&
    value.isFinite &&
    !value.toString().contains('e') &&
    (value.toString().split('.').elementAtOrNull(1)?.length ?? 0) <= 2;
String? _iso(Object? value) =>
    value is DateTime ? value.toUtc().toIso8601String() : null;
DateTime? _parseIso(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value))
    return null;
  return DateTime.tryParse(value)?.toUtc();
}
