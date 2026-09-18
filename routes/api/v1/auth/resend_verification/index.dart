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
    final rows = await pool.execute(
      Sql.named(
        '''SELECT email, email_verified_at FROM users WHERE id = @id''',
      ),
      parameters: {'id': userId},
    );
    if (rows.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or invalid',
      );
    }
    if (rows.first[1] == null) {
      await pool.execute(
        Sql.named('''UPDATE auth_tokens SET used_at = CURRENT_TIMESTAMP
          WHERE user_id = @user_id AND purpose = 'email_verification'
            AND used_at IS NULL'''),
        parameters: {'user_id': userId},
      );
      final issued = await AuthTokenService(
        pool,
      ).issue(userId, 'email_verification', const Duration(hours: 24));
      await EmailService().sendVerification(
        email: rows.first[0] as String,
        token: issued.token,
      );
    }
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'If email is unverified, verification instructions were sent',
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
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Verification request failed',
    );
  }
}
