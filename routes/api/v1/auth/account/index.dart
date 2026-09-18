import 'dart:async';
import 'dart:io';

import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

FutureOr<Response> onRequest(RequestContext context) =>
    authMiddleware(_handle)(context);

Future<Response> _handle(RequestContext context) async {
  if (context.request.method != HttpMethod.delete) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  try {
    final body = await context.request.json();
    final password = body is Map<String, dynamic> ? body['password'] : null;
    if (password is! String || password.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid password',
      );
    }

    final pool = context.read<Pool<dynamic>>();
    final userId = context.read<AuthSession>().userId;
    final deleted = await pool.runTx((transaction) async {
      final rows = await transaction.execute(
        Sql.named('SELECT password_hash FROM users WHERE id = @id'),
        parameters: {'id': userId},
      );
      if (rows.isEmpty ||
          !PasswordUtils.verify(password, rows.single[0] as String)) {
        return false;
      }
      final result = await transaction.execute(
        Sql.named('DELETE FROM users WHERE id = @id'),
        parameters: {'id': userId},
      );
      return result.affectedRows == 1;
    });

    if (!deleted) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid password',
      );
    }
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Account deleted successfully',
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Account deletion failed',
    );
  }
}
