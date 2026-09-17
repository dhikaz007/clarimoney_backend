import 'package:dart_frog/dart_frog.dart';

Response apiResponse({
  required int statusCode,
  required String message,
  Object? data,
  Map<String, Object?>? meta,
}) {
  return Response.json(
    statusCode: statusCode,
    body: {
      'status_code': statusCode,
      'message': message,
      'data': ?data,
      ...?meta,
    },
  );
}
