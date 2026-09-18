import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:mocktail/mocktail.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../routes/api/v1/auth/login.dart' as login;
import '../../routes/api/v1/auth/logout/index.dart' as logout;
import '../../routes/api/v1/auth/logout/_middleware.dart' as logout_middleware;
import '../../routes/api/v1/auth/logout_all/index.dart' as logout_all;
import '../../routes/api/v1/auth/refresh.dart' as refresh;
import '../../routes/api/v1/auth/sessions/[id].dart' as session_id;
import '../../routes/api/v1/auth/sessions/_middleware.dart'
    as sessions_middleware;
import '../../routes/api/v1/auth/register.dart' as register;

class _MockAuthRequestContext extends Mock implements RequestContext {}

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

  for (final route in ['register', 'login']) {
    test('$route rejects device name longer than 255 characters', () async {
      final request = TestRequestContext(
        path: '/api/v1/auth/$route',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': 'user@example.com',
          'password': 'password123',
          'device_id': 'device-id',
          'device_name': 'x' * 256,
        }),
      );

      final response = route == 'register'
          ? await register.onRequest(request.context)
          : await login.onRequest(request.context);
      final body = await response.json() as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.badRequest);
      expect(body['message'], 'device_name must be 255 characters or fewer');
    });
  }

  for (final route in ['register', 'login']) {
    test('$route accepts 255 emoji device name', () async {
      final request = TestRequestContext(
        path: '/api/v1/auth/$route',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': 'user@example.com',
          'password': 'password123',
          'device_id': 'device-id',
          'device_name': '😀' * 255,
        }),
      );
      final response = route == 'register'
          ? await register.onRequest(request.context)
          : await login.onRequest(request.context);
      expect(response.statusCode, isNot(HttpStatus.badRequest));
    });
  }

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
      final response = await register.onRequest(_withPool(request, pool));
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
      final response = await login.onRequest(_withPool(request, pool));
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

  test('register rolls back user when session creation fails', () async {
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
          'device_name': '\u0000',
        }),
      );
      final response = await register.onRequest(_withPool(request, pool));

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
      final firstRequest = TestRequestContext(
        path: '/api/v1/auth/login',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': '$userId@example.com',
          'password': 'password123',
          'device_id': 'same-device',
          'device_name': 'Old name',
        }),
      );
      firstRequest.provide<Pool<dynamic>>(pool);
      final first = await login.onRequest(firstRequest.context);
      final secondRequest = TestRequestContext(
        path: '/api/v1/auth/login',
        method: HttpMethod.post,
        body: jsonEncode({
          'email': '$userId@example.com',
          'password': 'password123',
          'device_id': 'same-device',
          'device_name': 'New name',
        }),
      );
      secondRequest.provide<Pool<dynamic>>(pool);
      final second = await login.onRequest(secondRequest.context);
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
      expect(firstData['session_id'], isNot(secondData['session_id']));
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

      final oldAccess = JwtUtils.verifyClaims(
        firstData['access_token'] as String,
      );
      final oldAccessCheck =
          await authMiddleware((_) async => Response(body: 'ok'))(
            _withPool(
              TestRequestContext(
                path: '/api/v1/transactions',
                headers: {
                  'authorization': 'Bearer ${firstData['access_token']}',
                },
              ),
              pool,
            ),
          );
      expect(oldAccess?['sid'], isNot(secondData['session_id']));
      expect(oldAccessCheck.statusCode, HttpStatus.unauthorized);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test(
    'refresh rotates token without extending fixed session expiry',
    () async {
      final pool = _pool();
      final userId = const Uuid().v4();
      try {
        await _insertUser(pool, userId, password: 'password123');
        final loggedIn = await login.onRequest(_loginRequest(userId, pool));
        final data =
            (await loggedIn.json() as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final before = await pool.execute(
          Sql.named('SELECT expires_at FROM user_sessions WHERE id = @id'),
          parameters: {'id': data['session_id']},
        );
        final beforeExpiry = before.single[0] as DateTime;
        final beforeNow = DateTime.now().toUtc();
        expect(
          (beforeExpiry.difference(beforeNow) -
                  SessionService.refreshTokenLifetime)
              .abs()
              .inSeconds,
          lessThan(2),
        );
        final response = await refresh.onRequest(
          _withPool(
            TestRequestContext(
              path: '/api/v1/auth/refresh',
              method: HttpMethod.post,
              body: jsonEncode({'refresh_token': data['refresh_token']}),
            ),
            pool,
          ),
        );
        final refreshed =
            (await response.json() as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final after = await pool.execute(
          Sql.named('SELECT expires_at FROM user_sessions WHERE id = @id'),
          parameters: {'id': data['session_id']},
        );
        final afterExpiry = after.single[0] as DateTime;

        expect(response.statusCode, HttpStatus.ok);
        expect(refreshed['refresh_token'], isNot(data['refresh_token']));
        expect(
          (afterExpiry.difference(beforeExpiry)).abs().inSeconds,
          lessThan(2),
        );
        expect(
          await SessionService(
            pool,
          ).rotateRefreshToken(data['refresh_token'] as String),
          isNull,
        );
      } finally {
        await _deleteUser(pool, userId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test(
    'current logout is idempotent and cross-user revoke is denied',
    () async {
      final pool = _pool();
      final ownerId = const Uuid().v4();
      final otherId = const Uuid().v4();
      try {
        await _insertUser(pool, ownerId, password: 'password123');
        await _insertUser(pool, otherId, password: 'password123');
        final owner = await login.onRequest(_loginRequest(ownerId, pool));
        final other = await login.onRequest(_loginRequest(otherId, pool));
        final ownerData =
            (await owner.json() as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final otherData =
            (await other.json() as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final crossRequest = TestRequestContext(
          path: '/api/v1/auth/sessions/${ownerData['session_id']}',
          method: HttpMethod.delete,
        );
        crossRequest.provide<Pool<dynamic>>(pool);
        crossRequest.provide<String>(otherId);
        final cross = await session_id.onRequest(
          crossRequest.context,
          ownerData['session_id'] as String,
        );

        expect(cross.statusCode, HttpStatus.ok);
        expect(otherData['session_id'], isNot(ownerData['session_id']));
        final target = await pool.execute(
          Sql.named('SELECT revoked_at FROM user_sessions WHERE id = @id'),
          parameters: {'id': ownerData['session_id']},
        );
        expect(target.single[0], isNull);

        final logoutRequest = TestRequestContext(
          path: '/api/v1/auth/logout',
          method: HttpMethod.post,
        );
        logoutRequest.provide<Pool<dynamic>>(pool);
        logoutRequest.provide<AuthSession>(
          AuthSession(ownerId, ownerData['session_id'] as String),
        );
        expect(
          (await logout.onRequest(logoutRequest.context)).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await logout.onRequest(logoutRequest.context)).statusCode,
          HttpStatus.ok,
        );
      } finally {
        await _deleteUser(pool, ownerId);
        await _deleteUser(pool, otherId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test('logout-all retry remains idempotent', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId, password: 'password123');
      final loggedIn = await login.onRequest(_loginRequest(userId, pool));
      final data =
          (await loggedIn.json() as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final request = TestRequestContext(
        path: '/api/v1/auth/logout-all',
        method: HttpMethod.post,
      );
      request.provide<Pool<dynamic>>(pool);
      request.provide<AuthSession>(
        AuthSession(userId, data['session_id'] as String),
      );

      expect(
        (await logout_all.onRequest(request.context)).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await logout_all.onRequest(request.context)).statusCode,
        HttpStatus.ok,
      );
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test(
    'session revoke middleware denies cross-user target ownership',
    () async {
      final pool = _pool();
      final ownerId = const Uuid().v4();
      final otherId = const Uuid().v4();
      try {
        await _insertUser(pool, ownerId, password: 'password123');
        await _insertUser(pool, otherId, password: 'password123');
        final owner = await login.onRequest(_loginRequest(ownerId, pool));
        final other = await login.onRequest(_loginRequest(otherId, pool));
        final ownerData =
            (await owner.json() as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final otherData =
            (await other.json() as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final request = _MockAuthRequestContext();
        when(() => request.request).thenReturn(
          Request(
            'DELETE',
            Uri.parse(
              'https://test.com/api/v1/auth/sessions/${ownerData['session_id']}',
            ),
            headers: {'authorization': 'Bearer ${otherData['access_token']}'},
          ),
        );
        when(() => request.provide<String>(any())).thenReturn(request);
        when(() => request.provide<AuthSession>(any())).thenReturn(request);
        when(() => request.read<Pool<dynamic>>()).thenReturn(pool);
        when(() => request.read<String>()).thenReturn(otherId);
        when(
          () => request.read<AuthSession>(),
        ).thenReturn(AuthSession(otherId, otherData['session_id'] as String));
        final response = await sessions_middleware.middleware(
          (context) =>
              session_id.onRequest(context, ownerData['session_id'] as String),
        )(request);
        final target = await pool.execute(
          Sql.named('SELECT revoked_at FROM user_sessions WHERE id = @id'),
          parameters: {'id': ownerData['session_id']},
        );

        expect(response.statusCode, HttpStatus.ok);
        expect(target.single[0], isNull);
      } finally {
        await _deleteUser(pool, ownerId);
        await _deleteUser(pool, otherId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test('expired access token remains rejected for logout', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId, password: 'password123');
      final loggedIn = await login.onRequest(_loginRequest(userId, pool));
      final data =
          (await loggedIn.json() as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final claims = JwtUtils.verifyClaims(data['access_token'] as String)!;
      final expired = JWT({
        ...claims,
        'exp':
            DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }).sign(SecretKey(Platform.environment['JWT_SECRET']!));
      final response = await logout_middleware.middleware(logout.onRequest)(
        _requestWithPool(
          TestRequestContext(
            path: '/api/v1/auth/logout',
            method: HttpMethod.post,
            headers: {'authorization': 'Bearer $expired'},
          ),
          pool,
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);
}

RequestContext _loginRequest(String userId, Pool<dynamic> pool) => _withPool(
  TestRequestContext(
    path: '/api/v1/auth/login',
    method: HttpMethod.post,
    body: jsonEncode({
      'email': '$userId@example.com',
      'password': 'password123',
      'device_id': userId,
    }),
  ),
  pool,
);

RequestContext _withPool(TestRequestContext request, Pool<dynamic> pool) {
  request.provide<Pool<dynamic>>(pool);
  return request.context;
}

RequestContext _requestWithPool(
  TestRequestContext request,
  Pool<dynamic> pool,
) => _withPool(request, pool);

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
