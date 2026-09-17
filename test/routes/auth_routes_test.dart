import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
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

  for (final value in [
    null,
    '',
    '  ',
    123,
    List<String>.filled(256, 'x').join(),
  ]) {
    test('register rejects invalid device ID $value', () async {
      final request = TestRequestContext(
        path: '/api/v1/auth/register',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': 'user@example.com',
          'password': 'password123',
          'device_id': value,
        }),
      );

      final response = await register.onRequest(request.context);
      final body = await response.json() as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        body['message'],
        'device_id must be a non-empty string of 255 characters or fewer',
      );
    });

    test('login rejects invalid device ID $value', () async {
      final request = TestRequestContext(
        path: '/api/v1/auth/login',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': 'user@example.com',
          'password': 'password123',
          'device_id': value,
        }),
      );

      final response = await login.onRequest(request.context);
      final body = await response.json() as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        body['message'],
        'device_id must be a non-empty string of 255 characters or fewer',
      );
    });
  }

  test('register rejects non-string device name', () async {
    final request = TestRequestContext(
      path: '/api/v1/auth/register',
      method: HttpMethod.post,
      body: jsonEncode({
        'email': 'user@example.com',
        'password': 'password123',
        'device_id': 'device-id',
        'device_name': 123,
      }),
    );

    final response = await register.onRequest(request.context);
    final body = await response.json() as Map<String, dynamic>;

    expect(response.statusCode, HttpStatus.badRequest);
    expect(body['message'], 'device_name must be a string');
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

  test('login returns session response fields', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId, password: 'password123');
      final request = TestRequestContext(
        path: '/api/v1/auth/login',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': '$userId@example.com',
          'password': 'password123',
          'device_id': userId,
        }),
      );
      final response = await login.onRequest(
        request.context.provide<Pool<dynamic>>(() => pool),
      );
      final body = await response.json() as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.ok);
      expect(
        data.keys,
        containsAll(['access_token', 'refresh_token', 'session_id', 'token']),
      );
      expect(data['access_token'], data['token']);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('register removes user when session creation fails', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final email = '$userId@example.com';
    try {
      final request = TestRequestContext(
        path: '/api/v1/auth/register',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': email,
          'password': 'password123',
          'device_id': userId,
          'device_name': 'x' * 256,
        }),
      );
      final response = await register.onRequest(
        request.context.provide<Pool<dynamic>>(() => pool),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(
        await pool.execute(
          Sql.named('SELECT id FROM users WHERE id = @id'),
          parameters: {'id': userId},
        ),
        isEmpty,
      );
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('login replaces same-device session metadata', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId, password: 'password123');
      final first = await login.onRequest(
        TestRequestContext(
          path: '/api/v1/auth/login',
          method: HttpMethod.post,
          body: jsonEncode({
            'email': '$userId@example.com',
            'password': 'password123',
            'device_id': 'same-device',
            'device_name': 'Old name',
          }),
        ).context.provide<Pool<dynamic>>(() => pool),
      );
      final second = await login.onRequest(
        TestRequestContext(
          path: '/api/v1/auth/login',
          method: HttpMethod.post,
          body: jsonEncode({
            'email': '$userId@example.com',
            'password': 'password123',
            'device_id': 'same-device',
            'device_name': 'New name',
          }),
        ).context.provide<Pool<dynamic>>(() => pool),
      );
      final firstData =
          (await first.json() as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final secondData =
          (await second.json() as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final sessions = await pool.execute(
        Sql.named(
          'SELECT id, device_name FROM user_sessions WHERE user_id = @user_id AND device_id = @device_id',
        ),
        parameters: {'user_id': userId, 'device_id': 'same-device'},
      );

      expect(first.statusCode, HttpStatus.ok);
      expect(second.statusCode, HttpStatus.ok);
      expect(firstData['session_id'], secondData['session_id']);
      expect(firstData['refresh_token'], isNot(secondData['refresh_token']));
      expect(sessions.single[0], secondData['session_id']);
      expect(sessions.single[1], 'New name');
      expect(sessions, hasLength(1));

      expect(
        await SessionService(
          pool,
        ).rotateRefreshToken(firstData['refresh_token'] as String),
        isNull,
      );
      final revoked = await pool.execute(
        Sql.named('SELECT revoked_at FROM user_sessions WHERE id = @id'),
        parameters: {'id': secondData['session_id']},
      );
      expect(revoked.single[0], isNotNull);
    } finally {
      await _deleteUser(pool, userId);
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

Future<void> _insertUser(
  Pool<dynamic> pool,
  String userId, {
  required String password,
}) => pool.execute(
  Sql.named(
    'INSERT INTO users (id, email, password_hash) VALUES (@id, @email, @password_hash)',
  ),
  parameters: {
    'id': userId,
    'email': '$userId@example.com',
    'password_hash': PasswordUtils.hash(password),
  },
);

Future<void> _deleteUser(Pool<dynamic> pool, String userId) => pool.execute(
  Sql.named('DELETE FROM users WHERE id = @id'),
  parameters: {'id': userId},
);
