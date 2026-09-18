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
      message: 'Invalid category id',
    );
  }
  if (method != HttpMethod.put && method != HttpMethod.patch) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }
  late final Map<String, dynamic> body;
  try {
    body = decodeObject(await context.request.body());
  } on FormatException {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Invalid JSON body',
    );
  }
  if ((body['name'] != null && body['name'] is! String) ||
      (body['status'] != null && body['status'] is! String)) {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Invalid category update',
    );
  }
  final action = body['status'] as String?;
  final name = (body['name'] as String?)?.trim();
  if (name != null && (name.isEmpty || name.length > 50)) {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Name must contain 1-50 characters',
    );
  }
  if (action != null && action != 'active' && action != 'archived') {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'Invalid category status',
    );
  }
  if (name == null && action == null) {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'name or status required',
    );
  }
  try {
    final result = await context.read<Pool<dynamic>>().execute(
      Sql.named(
        '''UPDATE categories SET name = COALESCE(@name, name), status = COALESCE(@status, status)
        WHERE id = @id AND user_id = @userId''',
      ),
      parameters: {
        'id': id,
        'userId': context.read<String>(),
        'name': name,
        'status': action,
      },
    );
    if (result.affectedRows == 0) {
      return apiResponse(
        statusCode: HttpStatus.notFound,
        message: 'Category not found',
      );
    }
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Category updated successfully',
      data: {
        'id': id,
        if (name != null) 'name': name,
        if (action != null) 'status': action,
      },
    );
  } on ServerException catch (error) {
    return apiResponse(
      statusCode: error.code == '23505'
          ? HttpStatus.conflict
          : HttpStatus.badRequest,
      message: error.code == '23505'
          ? 'Category already exists'
          : 'Invalid category update',
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Failed to update category',
    );
  }
}
