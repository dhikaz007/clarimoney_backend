import 'dart:io';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:clarimoney_backend/src/auth_middleware.dart';
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
    final auth = context.read<AuthSession>();
    await SessionService(
      context.read<Pool<dynamic>>(),
    ).revokeSession(auth.sessionId, auth.userId);
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Logged out successfully',
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Logout failed',
    );
  }
}
