import 'dart:async';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/transaction_validation.dart';

FutureOr<Response> onRequest(RequestContext context, String id) async {
  final method = context.request.method;
  if (!validUuid(id)) {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Invalid transaction id',
    );
  }

  if (method == HttpMethod.delete) {
    final userId = context.read<String>();
    final pool = context.read<Pool<dynamic>>();
    try {
      final result = await pool.execute(
        Sql.named('''
        DELETE FROM transactions
        WHERE id = @id AND user_id = @userId
      '''),
        parameters: {'id': id, 'userId': userId},
      );
      if (result.affectedRows == 0) {
        return apiResponse(
          statusCode: HttpStatus.notFound,
          message: 'Transaction not found',
        );
      }
      return apiResponse(
        statusCode: HttpStatus.ok,
        message: 'Transaction deleted successfully',
      );
    } catch (_) {
      return apiResponse(
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to delete transaction',
      );
    }
  }

  if (method == HttpMethod.get) {
    final userId = context.read<String>();
    final pool = context.read<Pool<dynamic>>();
    try {
      final result = await pool.execute(
        Sql.named('''
      SELECT t.id, t.type, t.category_id, t.amount, t.date, t.note, t.created_at,
             c.name, c.color, c.icon
      FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.id = @id AND t.user_id = @userId
    '''),
        parameters: {'id': id, 'userId': userId},
      );
      if (result.isEmpty) {
        return apiResponse(
          statusCode: HttpStatus.notFound,
          message: 'Transaction not found',
        );
      }
      final row = result.single;
      return apiResponse(
        statusCode: HttpStatus.ok,
        message: 'Transaction fetched successfully',
        data: {
          'id': row[0],
          'type': row[1],
          'category_id': row[2],
          'amount': row[3],
          'date': _iso(row[4]),
          'note': row[5],
          'created_at': _iso(row[6]),
          'category': {'name': row[7], 'color': row[8], 'icon': row[9]},
        },
      );
    } catch (_) {
      return apiResponse(
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to fetch transaction',
      );
    }
  }

  if (method != HttpMethod.put) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  try {
    final body = decodeObject(await context.request.body());
    final userId = context.read<String>();
    final pool = context.read<Pool<dynamic>>();
    final categoryId = body['category_id'] as String?;
    final rawType = body['type'];
    if (rawType != null && rawType is! String) {
      throw const FormatException('Invalid type');
    }
    final type = rawType as String?;
    final amount = body['amount'] as num?;
    final date = fullIsoDate(body['date']);
    if (categoryId == null ||
        !_validAmount(amount) ||
        date == null ||
        (type != null && type != 'income' && type != 'expense')) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Valid category_id, positive amount, and date required',
      );
    }

    final existing = await pool.execute(
      Sql.named('''
        SELECT type FROM transactions
        WHERE id = @id AND user_id = @userId
      '''),
      parameters: {'id': id, 'userId': userId},
    );
    if (existing.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.notFound,
        message: 'Transaction not found',
      );
    }
    final effectiveType = type ?? existing.single[0] as String;

    final category = await pool.execute(
      Sql.named('''
         SELECT id FROM categories
         WHERE id = @categoryId AND (user_id = @userId OR user_id IS NULL)
           AND type = @type AND status = 'active'
      '''),
      parameters: {
        'categoryId': categoryId,
        'userId': userId,
        'type': effectiveType,
      },
    );
    if (category.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Invalid category',
      );
    }

    final result = await pool.execute(
      Sql.named('''
        UPDATE transactions
         SET type = @type, category_id = @categoryId, amount = @amount, date = @date, note = @note
        WHERE id = @id AND user_id = @userId
      '''),
      parameters: {
        'id': id,
        'userId': userId,
        'categoryId': categoryId,
        'type': effectiveType,
        'amount': amount,
        'date': date.toUtc(),
        'note': _note(body['note']),
      },
    );
    if (result.affectedRows == 0) {
      return apiResponse(
        statusCode: HttpStatus.notFound,
        message: 'Transaction not found',
      );
    }
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Transaction updated successfully',
      data: {'id': id},
    );
  } on FormatException {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Invalid request body',
    );
  } on ServerException catch (e) {
    if (e.code == '23514' || e.code == '23503') {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Invalid transaction',
      );
    }
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Failed to update transaction',
    );
  } on TypeError {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Invalid request body',
    );
  }
}

bool _validAmount(num? value) =>
    value != null &&
    value > 0 &&
    value.isFinite &&
    !value.toString().contains('e') &&
    (value.toString().split('.').elementAtOrNull(1)?.length ?? 0) <= 2;
String? _iso(Object? value) =>
    value is DateTime ? value.toUtc().toIso8601String() : null;
String? _note(Object? value) => trimmedNote(value);
