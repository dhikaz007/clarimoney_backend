import 'dart:async';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:clarimoney_backend/src/api_response.dart';

FutureOr<Response> onRequest(RequestContext context) async {
  final pool = context.read<Pool<dynamic>>();
  try {
    final result = await pool.execute('SELECT 1 as alive');
    final row = result.first;
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'ClariMoney backend active',
      data: {'db': row.first == 1 ? 'connected' : 'unknown'},
    );
  } catch (e) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Database connection failed',
    );
  }
}
