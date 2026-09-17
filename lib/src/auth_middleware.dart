import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import 'utils/jwt_utils.dart';
import 'api_response.dart';

Handler authMiddleware(Handler handler) {
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
    if (userId is! String || tokenVersion is! int) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or invalid',
      );
    }

    final pool = context.read<Pool<dynamic>>();
    final result = await pool.execute(
      Sql.named('SELECT token_version FROM users WHERE id = @id'),
      parameters: {'id': userId},
    );
    if (result.isEmpty || result.first[0] != tokenVersion) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or revoked',
      );
    }

    return handler(context.provide<String>(() => userId));
  };
}
