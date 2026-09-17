import 'dart:io';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.delete) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }
  try {
    await SessionService(
      context.read<Pool<dynamic>>(),
    ).revokeSession(id, context.read<String>());
    return apiResponse(statusCode: HttpStatus.ok, message: 'Session revoked');
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Session revoke failed',
    );
  }
}
