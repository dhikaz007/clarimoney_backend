import 'dart:io';

import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }
  try {
    final userId = context.read<AuthSession>().userId;
    final rows = await context.read<Pool<dynamic>>().execute(
      Sql.named(
        '''SELECT id, email, email_verified_at FROM users WHERE id = @id''',
      ),
      parameters: {'id': userId},
    );
    if (rows.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or invalid',
      );
    }
    final row = rows.first;
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Profile fetched successfully',
      data: {'id': row[0], 'email': row[1], 'email_verified': row[2] != null},
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Profile fetch failed',
    );
  }
}
