import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:test/test.dart';

import '../../routes/api/v1/auth/login.dart' as login;
import '../../routes/api/v1/auth/register.dart' as register;

void main() {
  test('register rejects invalid credentials before database access', () async {
    final request = TestRequestContext(
      path: '/api/v1/auth/register',
      method: HttpMethod.post,
      body: jsonEncode({'email': 'bad-email', 'password': 'short'}),
    );

    final response = await register.onRequest(request.context);

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('login rejects missing credentials before database access', () async {
    final request = TestRequestContext(
      path: '/api/v1/auth/login',
      method: HttpMethod.post,
      body: jsonEncode({'email': 'user@example.com'}),
    );

    final response = await login.onRequest(request.context);

    expect(response.statusCode, HttpStatus.badRequest);
  });
}
