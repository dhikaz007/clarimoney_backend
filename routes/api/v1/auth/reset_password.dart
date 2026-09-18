import 'dart:io';

import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:clarimoney_backend/src/services/auth_token_service.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  try {
    final body = await context.request.json();
    final token = body is Map<String, dynamic> && body['token'] is String
        ? body['token'] as String
        : null;
    final password = body is Map<String, dynamic> && body['password'] is String
        ? body['password'] as String
        : null;
    if (token == null ||
        token.isEmpty ||
        password == null ||
        password.length < 8) {
      return _invalid();
    }

    final pool = context.read<Pool<dynamic>>();
    final changed = await pool.runTx((transaction) async {
      final userId = await AuthTokenService(
        pool,
      ).consumeInTransaction(transaction, token, 'password_reset');
      if (userId == null) return false;
      final updated = await transaction.execute(
        Sql.named('''UPDATE users
          SET password_hash = @password_hash,
              token_version = token_version + 1
          WHERE id = @user_id'''),
        parameters: {
          'user_id': userId,
          'password_hash': PasswordUtils.hash(password),
        },
      );
      if (updated.affectedRows != 1) return false;
      await SessionService(pool).revokeAllInTransaction(transaction, userId);
      return true;
    });
    return changed
        ? apiResponse(
            statusCode: HttpStatus.ok,
            message: 'Password reset successfully',
          )
        : _invalid();
  } catch (_) {
    return _invalid();
  }
}

Response _invalid() => apiResponse(
  statusCode: HttpStatus.badRequest,
  message: 'Invalid or expired password reset request',
);
