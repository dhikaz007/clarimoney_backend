import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import 'utils/jwt_utils.dart';
import 'api_response.dart';

class AuthSession {
  const AuthSession(this.userId, this.sessionId);

  final String userId;
  final String sessionId;
}

Handler authMiddleware(Handler handler, {bool allowRevokedSession = false}) {
  return (context) async {
    if (context.request.method == HttpMethod.options) {
      return apiResponse(
        statusCode: HttpStatus.ok,
        message: 'Preflight request accepted',
      );
    }

    final value = context.request.headers['authorization'];
    if (value == null || !value.startsWith('Bearer ')) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Missing or invalid token',
      );
    }

    final claims = JwtUtils.verifyClaims(value.substring(7).trim());
    final userId = claims?['sub'];
    final tokenVersion = claims?['ver'];
    final sessionId = claims?['sid'];
    if (userId is! String || tokenVersion is! int || sessionId is! String) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or invalid',
      );
    }

    final pool = context.read<Pool<dynamic>>();
    late final Result result;
    try {
      result = await pool.execute(
        Sql.named('''
          SELECT u.token_version
          FROM users u
          JOIN user_sessions s ON s.user_id = u.id
          WHERE u.id = @id AND s.id = @session_id
            AND s.expires_at > CURRENT_TIMESTAMP
            AND (
              @allow_revoked OR
              (s.revoked_at IS NULL AND s.expires_at > CURRENT_TIMESTAMP)
            )
        '''),
        parameters: {
          'id': userId,
          'session_id': sessionId,
          'allow_revoked': allowRevokedSession,
        },
      );
    } catch (_) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or invalid',
      );
    }
    if (result.isEmpty || result.first[0] != tokenVersion) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or revoked',
      );
    }

    return handler(
      context
          .provide<String>(() => userId)
          .provide<AuthSession>(() => AuthSession(userId, sessionId)),
    );
  };
}
