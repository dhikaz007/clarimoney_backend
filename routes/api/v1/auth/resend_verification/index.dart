import 'dart:io';

import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:clarimoney_backend/src/services/auth_token_service.dart';
import 'package:clarimoney_backend/src/services/email_service.dart';
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
    final userId = context.read<AuthSession>().userId;
    final pool = context.read<Pool<dynamic>>();
    final emailService = _emailService(context);
    final user = await pool.execute(
      Sql.named('''SELECT email_verified_at FROM users WHERE id = @id'''),
      parameters: {'id': userId},
    );
    if (user.isEmpty) throw _InvalidUserException();
    if (user.first[0] != null) return _success();
    emailService.validateConfiguration();
    await pool.runTx((transaction) async {
      final rows = await transaction.execute(
        Sql.named('''SELECT email, email_verified_at FROM users
          WHERE id = @id FOR UPDATE'''),
        parameters: {'id': userId},
      );
      if (rows.isEmpty) throw _InvalidUserException();
      if (rows.first[1] != null) return;
      await transaction.execute(
        Sql.named('''UPDATE auth_tokens SET used_at = CURRENT_TIMESTAMP
          WHERE user_id = @user_id AND purpose = 'email_verification'
            AND used_at IS NULL'''),
        parameters: {'user_id': userId},
      );
      final issued = await AuthTokenService(pool).issueInTransaction(
        transaction,
        userId,
        'email_verification',
        const Duration(hours: 24),
      );
      await emailService.sendVerification(
        email: rows.first[0] as String,
        token: issued.token,
      );
    });
    return _success();
  } on _InvalidUserException {
    return apiResponse(
      statusCode: HttpStatus.unauthorized,
      message: 'Token expired or invalid',
    );
  } on EmailConfigurationException catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Verification email unavailable',
    );
  } on EmailSendException catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Verification email unavailable',
    );
  } on EmailSendTimeoutException catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Verification email unavailable',
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Verification request failed',
    );
  }
}

Response _success() => apiResponse(
  statusCode: HttpStatus.ok,
  message: 'If email is unverified, verification instructions were sent',
);

class _InvalidUserException implements Exception {}

EmailService _emailService(RequestContext context) {
  try {
    return context.read<EmailService>();
  } on Object {
    return EmailService();
  }
}
