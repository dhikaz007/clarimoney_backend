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

      final offset = (page - 1) * limit;
      final countResult = await pool.execute(
        Sql.named('''
          SELECT COUNT(*)
          FROM transactions
          WHERE user_id = @userId
        '''),
        parameters: {'userId': userId},
      );
      final total = (countResult.first.first as int?) ?? 0;

      final result = await pool.execute(
        Sql.named('''
          SELECT t.id, t.category_id, t.amount, t.date, t.created_at, c.name, c.color, c.icon
          FROM transactions t
          LEFT JOIN categories c ON t.category_id = c.id
          WHERE t.user_id = @userId
          ORDER BY t.date DESC, t.created_at DESC
          LIMIT @limit OFFSET @offset
        '''),
        parameters: {'userId': userId, 'limit': limit, 'offset': offset},
      );

      final transactions = result.map((row) {
        return {
          'id': row[0],
          'category_id': row[1],
          'amount': row[2],
          'date': (row[3] as DateTime?)?.toIso8601String(),
          'created_at': (row[4] as DateTime?)?.toIso8601String(),
          'category': {'name': row[5], 'color': row[6], 'icon': row[7]},
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
      final amount = body['amount'] as num?;
      final dateRaw = body['date'] as String?;

      if (categoryId == null ||
          amount == null ||
          amount <= 0 ||
          dateRaw == null) {
        return apiResponse(
          statusCode: HttpStatus.badRequest,
          message: 'category_id, amount, and date required',
        );
      }

      final date = DateTime.tryParse(dateRaw);
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
        '''),
        parameters: {'categoryId': categoryId, 'userId': userId},
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
          INSERT INTO transactions (id, user_id, category_id, amount, date)
          VALUES (@id, @userId, @categoryId, @amount, @date)
        '''),
        parameters: {
          'id': id,
          'userId': userId,
          'categoryId': categoryId,
          'amount': amount,
          'date': date,
        },
      );

      return apiResponse(
        statusCode: HttpStatus.created,
        message: 'Transaction created successfully',
        data: {'id': id},
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
