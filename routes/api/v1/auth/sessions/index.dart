import 'dart:io';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }
  try {
    final userId = context.read<String>();
    final sessions = await SessionService(
      context.read<Pool<dynamic>>(),
    ).listSessions(userId);
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Sessions retrieved',
      data: sessions,
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Sessions lookup failed',
    );
  }
}
