import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

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

  test('register rejects missing device ID before database access', () async {
    final request = TestRequestContext(
      path: '/api/v1/auth/register',
      method: HttpMethod.post,
      body: jsonEncode({
        'email': 'user@example.com',
        'password': 'password123',
      }),
    );

    final response = await register.onRequest(request.context);

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('login rejects missing device ID before database access', () async {
    final request = TestRequestContext(
      path: '/api/v1/auth/login',
      method: HttpMethod.post,
      body: jsonEncode({
        'email': 'user@example.com',
        'password': 'password123',
      }),
    );

    final response = await login.onRequest(request.context);

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('register returns session response fields', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      final request = TestRequestContext(
        path: '/api/v1/auth/register',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': '$userId@example.com',
          'password': 'password123',
          'device_id': userId,
          'device_name': 'Test device',
        }),
      );
      final response = await register.onRequest(
        request.context.provide<Pool<dynamic>>(() => pool),
      );
      final body = await response.json() as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.created);
      expect(
        data.keys,
        containsAll(['access_token', 'refresh_token', 'session_id', 'token']),
      );
      expect(data['access_token'], data['token']);
    } finally {
      await pool.execute(
        Sql.named('DELETE FROM users WHERE id = @id'),
        parameters: {'id': userId},
      );
      await pool.close();
    }
  }, skip: _skipDbTest);
}

Pool<dynamic> _pool() {
  final url = Uri.parse(Platform.environment['DATABASE_URL']!);
  return Pool<dynamic>.withUrl(
    url
        .replace(
          queryParameters: {
            for (final entry in url.queryParameters.entries)
              if (entry.key != 'channel_binding') entry.key: entry.value,
          },
        )
        .toString(),
  );
}

bool get _skipDbTest =>
    Platform.environment['DATABASE_URL'] == null ||
    Platform.environment['JWT_SECRET'] == null;
