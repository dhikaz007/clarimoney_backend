import 'dart:io';

import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/services/auth_token_service.dart';
import 'package:clarimoney_backend/src/services/email_service.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

const _successMessage =
    'If an account exists, password reset instructions were sent';
const _minimumResponseTime = Duration(milliseconds: 250);

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  final started = Stopwatch()..start();
  try {
    final body = await context.request.json();
    final email = body is Map<String, dynamic> && body['email'] is String
        ? (body['email'] as String).trim().toLowerCase()
        : null;
    if (email != null && email.isNotEmpty) {
      final pool = context.read<Pool<dynamic>>();
      final emailService = _emailService(context);
      await pool.runTx((transaction) async {
        final users = await transaction.execute(
          Sql.named(
            'SELECT id, email FROM users WHERE email = @email FOR UPDATE',
          ),
          parameters: {'email': email},
        );
        if (users.isEmpty ||
            users.first[0] is! String ||
            users.first[1] is! String) {
          return;
        }
        final userId = users.first[0] as String;
        await transaction.execute(
          Sql.named('''UPDATE auth_tokens SET used_at = CURRENT_TIMESTAMP
            WHERE user_id = @user_id AND purpose = 'password_reset'
              AND used_at IS NULL'''),
          parameters: {'user_id': userId},
        );
        final issued = await AuthTokenService(pool).issueInTransaction(
          transaction,
          userId,
          'password_reset',
          const Duration(minutes: 30),
        );
        await emailService.sendPasswordReset(
          email: users.first[1] as String,
          token: issued.token,
        );
      });
    }
  } catch (_) {
    // Keep account existence undiscoverable through this endpoint.
  }

  final remaining = _minimumResponseTime - started.elapsed;
  if (remaining > Duration.zero) await Future<void>.delayed(remaining);

  return apiResponse(statusCode: HttpStatus.ok, message: _successMessage);
}

EmailService _emailService(RequestContext context) {
  try {
    return context.read<EmailService>();
  } on Object {
    return EmailService();
  }
}
