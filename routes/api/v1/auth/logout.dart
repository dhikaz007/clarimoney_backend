import 'dart:async';
import 'dart:io';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

FutureOr<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  final authorization = context.request.headers['authorization'];
  if (authorization == null || !authorization.startsWith('Bearer ')) {
    return apiResponse(
      statusCode: HttpStatus.unauthorized,
      message: 'Missing or invalid token',
    );
  }

  final claims = JwtUtils.verifyClaims(authorization.substring(7).trim());
  final userId = claims?['sub'];
  if (userId is! String) {
    return apiResponse(
      statusCode: HttpStatus.unauthorized,
      message: 'Token expired or invalid',
    );
  }

  try {
    final pool = context.read<Pool<dynamic>>();
    final result = await pool.execute(
      Sql.named('''
        UPDATE users
        SET token_version = token_version + 1
        WHERE id = @id
        RETURNING id
      '''),
      parameters: {'id': userId},
    );
    if (result.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Token expired or invalid',
      );
    }
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Logged out from all devices',
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Logout failed',
    );
  }
}
