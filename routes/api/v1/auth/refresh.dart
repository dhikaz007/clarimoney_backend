import 'dart:io';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
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
    final token = body is Map<String, dynamic> ? body['refresh_token'] : null;
    if (token is! String || token.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid refresh token',
      );
    }
    final rotated = await SessionService(
      context.read<Pool<dynamic>>(),
    ).rotateRefreshToken(token);
    if (rotated == null) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid refresh token',
      );
    }
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Token refreshed',
      data: {
        'access_token': rotated['accessToken'],
        'refresh_token': rotated['refreshToken'],
        'token': rotated['accessToken'],
      },
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.unauthorized,
      message: 'Invalid refresh token',
    );
  }
}
