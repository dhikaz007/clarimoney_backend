import 'dart:async';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:clarimoney_backend/src/api_response.dart';

FutureOr<Response> onRequest(RequestContext context, String id) async {
  final method = context.request.method;
  final userId = context.read<String>();
  final pool = context.read<Pool<dynamic>>();

  if (method == HttpMethod.delete) {
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
  }

  if (method != HttpMethod.put) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final categoryId = body['category_id'] as String?;
    final amount = body['amount'] as num?;
    final date = DateTime.tryParse(body['date'] as String? ?? '');
    if (categoryId == null || amount == null || amount <= 0 || date == null) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Valid category_id, positive amount, and date required',
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

    final result = await pool.execute(
      Sql.named('''
        UPDATE transactions
        SET category_id = @categoryId, amount = @amount, date = @date
        WHERE id = @id AND user_id = @userId
      '''),
      parameters: {
        'id': id,
        'userId': userId,
        'categoryId': categoryId,
        'amount': amount,
        'date': date,
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
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Invalid request body',
    );
  }
}
