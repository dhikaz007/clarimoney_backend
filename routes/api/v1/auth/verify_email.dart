import 'dart:io';

import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/utils/auth_token_utils.dart';
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
    final token = body is Map<String, dynamic> ? body['token'] : null;
    if (token is! String || token.isEmpty) return _invalid();
    final pool = context.read<Pool<dynamic>>();
    final verified = await pool.runTx((transaction) async {
      final rows = await transaction.execute(
        Sql.named('''SELECT user_id FROM auth_tokens
          WHERE token_hash = @hash AND purpose = 'email_verification'
            AND used_at IS NULL AND expires_at > CURRENT_TIMESTAMP
          FOR UPDATE'''),
        parameters: {'hash': AuthTokenUtils.hash(token)},
      );
      if (rows.isEmpty || rows.first[0] is! String) return false;
      final userId = rows.first[0] as String;
      final updated = await transaction.execute(
        Sql.named('''UPDATE users SET email_verified_at = CURRENT_TIMESTAMP
          WHERE id = @id AND email_verified_at IS NULL'''),
        parameters: {'id': userId},
      );
      if (updated.affectedRows != 1) return false;
      final consumed = await transaction.execute(
        Sql.named('''UPDATE auth_tokens SET used_at = CURRENT_TIMESTAMP
          WHERE token_hash = @hash AND purpose = 'email_verification'
            AND used_at IS NULL'''),
        parameters: {'hash': AuthTokenUtils.hash(token)},
      );
      return consumed.affectedRows == 1;
    });
    if (!verified) return _invalid();
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Email verified successfully',
      data: {'email_verified': true},
    );
  } catch (_) {
    return _invalid();
  }
}

Response _invalid() => apiResponse(
  statusCode: HttpStatus.badRequest,
  message: 'Invalid or expired verification token',
);
