import 'dart:io';

import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:test/test.dart';

void main() {
  test('rejects request without bearer token', () async {
    final request = TestRequestContext(path: '/api/v1/transactions');
    final response = await Future<Response>.value(
      authMiddleware((_) => Response(body: 'ok'))(request.context),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('rejects malformed bearer token', () async {
    final request = TestRequestContext(
      path: '/api/v1/transactions',
      headers: {'authorization': 'Bearer invalid'},
    );
    final response = await Future<Response>.value(
      authMiddleware((_) => Response(body: 'ok'))(request.context),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
  });
}
