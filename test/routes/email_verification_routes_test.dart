import 'dart:convert';
import 'dart:io';

import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:clarimoney_backend/src/services/email_service.dart';
import 'package:clarimoney_backend/src/utils/auth_token_utils.dart';
import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:mailer/mailer.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../routes/api/v1/auth/me/index.dart' as me;
import '../../routes/api/v1/auth/login.dart' as login;
import '../../routes/api/v1/auth/register.dart' as register;
import '../../routes/api/v1/auth/resend_verification/index.dart' as resend;
import '../../routes/api/v1/auth/verify_email.dart' as verify;

void main() {
  test('register reports email as unverified', () async {
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
        }),
      );
      final response = await register.onRequest(_withPool(request, pool));
      final body = await response.json() as Map<String, dynamic>;
      expect(response.statusCode, HttpStatus.created);
      expect((body['data'] as Map)['user']['email_verified'], false);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('profile reports verification state', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      final token = JwtUtils.generate(
        userId,
        tokenVersion: 0,
        sessionId: sessionId,
      );
      final request = TestRequestContext(
        path: '/api/v1/auth/me',
        method: HttpMethod.get,
        headers: {'authorization': 'Bearer $token'},
      );
      request.provide<AuthSession>(AuthSession(userId, sessionId));
      final response = await me.onRequest(_withPool(request, pool));
      final body = await response.json() as Map<String, dynamic>;
      expect(response.statusCode, HttpStatus.ok);
      expect((body['data'] as Map)['email_verified'], false);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('login remains available before email verification', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      final response = await login.onRequest(
        _withPool(
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
        ),
      );
      expect(response.statusCode, HttpStatus.ok);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('verification consumes token and rejects reuse', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final raw = AuthTokenUtils.generate();
    try {
      await _insertUser(pool, userId);
      await pool.execute(
        Sql.named(
          '''INSERT INTO auth_tokens
          (id, user_id, token_hash, purpose, expires_at)
          VALUES (@id, @user_id, @hash, 'email_verification', CURRENT_TIMESTAMP + INTERVAL '1 day')''',
        ),
        parameters: {
          'id': const Uuid().v4(),
          'user_id': userId,
          'hash': AuthTokenUtils.hash(raw),
        },
      );
      final request = TestRequestContext(
        path: '/api/v1/auth/verify-email',
        method: HttpMethod.post,
        body: jsonEncode({'token': raw}),
      );
      final first = await verify.onRequest(_withPool(request, pool));
      final second = await verify.onRequest(_withPool(request, pool));
      final state = await pool.execute(
        Sql.named('SELECT email_verified_at FROM users WHERE id = @id'),
        parameters: {'id': userId},
      );
      expect(first.statusCode, HttpStatus.ok);
      expect(second.statusCode, HttpStatus.badRequest);
      expect(state.single[0], isNotNull);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('expired verification token returns generic bad request', () async {
    final pool = _pool();
    final raw = AuthTokenUtils.generate();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await pool.execute(
        Sql.named(
          '''INSERT INTO auth_tokens
          (id, user_id, token_hash, purpose, expires_at)
          VALUES (@id, @user_id, @hash, 'email_verification', CURRENT_TIMESTAMP - INTERVAL '1 minute')''',
        ),
        parameters: {
          'id': const Uuid().v4(),
          'user_id': userId,
          'hash': AuthTokenUtils.hash(raw),
        },
      );
      final response = await verify.onRequest(
        _withPool(
          TestRequestContext(
            path: '/api/v1/auth/verify-email',
            method: HttpMethod.post,
            body: jsonEncode({'token': raw}),
          ),
          pool,
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('resend invalidates prior unused verification token', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    final raw = AuthTokenUtils.generate();
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      await pool.execute(
        Sql.named(
          '''INSERT INTO auth_tokens
          (id, user_id, token_hash, purpose, expires_at)
          VALUES (@id, @user_id, @hash, 'email_verification', CURRENT_TIMESTAMP + INTERVAL '1 day')''',
        ),
        parameters: {
          'id': const Uuid().v4(),
          'user_id': userId,
          'hash': AuthTokenUtils.hash(raw),
        },
      );
      final request = TestRequestContext(
        path: '/api/v1/auth/resend-verification',
        method: HttpMethod.post,
      );
      request.provide<AuthSession>(AuthSession(userId, sessionId));
      request.provide<EmailService>(
        EmailService(environment: _mailEnvironment, sender: (_, __) async {}),
      );
      final response = await resend.onRequest(_withPool(request, pool));
      final token = await pool.execute(
        Sql.named('SELECT used_at FROM auth_tokens WHERE token_hash = @hash'),
        parameters: {'hash': AuthTokenUtils.hash(raw)},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(token.single[0], isNotNull);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('resend for verified account succeeds without mail', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId, verified: true);
      final sessionId = const Uuid().v4();
      await pool.execute(
        Sql.named(
          '''INSERT INTO user_sessions
          (id, user_id, device_id, refresh_token_hash, expires_at)
          VALUES (@id, @user_id, 'email-test', 'hash', CURRENT_TIMESTAMP + INTERVAL '1 day')''',
        ),
        parameters: {'id': sessionId, 'user_id': userId},
      );
      final token = JwtUtils.generate(
        userId,
        tokenVersion: 0,
        sessionId: sessionId,
      );
      final request = TestRequestContext(
        path: '/api/v1/auth/resend-verification',
        method: HttpMethod.post,
        headers: {'authorization': 'Bearer $token'},
      );
      request.provide<AuthSession>(AuthSession(userId, sessionId));
      request.provide<EmailService>(
        EmailService(environment: _mailEnvironment, sender: (_, __) async {}),
      );
      final response = await resend.onRequest(_withPool(request, pool));
      expect(response.statusCode, HttpStatus.ok);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('resend issues one token and sends through injected sender', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    Message? sent;
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      final request = TestRequestContext(
        path: '/api/v1/auth/resend-verification',
        method: HttpMethod.post,
      );
      request.provide<AuthSession>(AuthSession(userId, sessionId));
      request.provide<EmailService>(
        EmailService(
          environment: _mailEnvironment,
          sender: (message, _) async => sent = message,
        ),
      );
      final response = await resend.onRequest(_withPool(request, pool));
      final valid = await _validVerificationTokens(pool, userId);
      expect(response.statusCode, HttpStatus.ok);
      expect(valid, hasLength(1));
      expect(sent, isNotNull);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('failed resend invalidates issued token', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      final request = TestRequestContext(
        path: '/api/v1/auth/resend-verification',
        method: HttpMethod.post,
      );
      request.provide<AuthSession>(AuthSession(userId, sessionId));
      request.provide<EmailService>(
        EmailService(
          environment: _mailEnvironment,
          sender: (_, __) => Future<void>.error(StateError('SMTP down')),
        ),
      );
      final response = await resend.onRequest(_withPool(request, pool));
      expect(response.statusCode, HttpStatus.internalServerError);
      expect(await _validVerificationTokens(pool, userId), isEmpty);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('invalid SMTP configuration issues no verification token', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      final request = TestRequestContext(
        path: '/api/v1/auth/resend-verification',
        method: HttpMethod.post,
      );
      request.provide<AuthSession>(AuthSession(userId, sessionId));
      request.provide<EmailService>(
        EmailService(environment: const {'SMTP_PORT': 'bad'}),
      );
      final response = await resend.onRequest(_withPool(request, pool));
      expect(response.statusCode, HttpStatus.internalServerError);
      expect(await _validVerificationTokens(pool, userId), isEmpty);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('concurrent resends leave one valid token', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      Future<Response> resendOnce() {
        final request = TestRequestContext(
          path: '/api/v1/auth/resend-verification',
          method: HttpMethod.post,
        );
        request.provide<AuthSession>(AuthSession(userId, sessionId));
        request.provide<EmailService>(
          EmailService(environment: _mailEnvironment, sender: (_, __) async {}),
        );
        return resend.onRequest(_withPool(request, pool));
      }

      final responses = await Future.wait([resendOnce(), resendOnce()]);
      expect(
        responses.map((response) => response.statusCode),
        everyElement(HttpStatus.ok),
      );
      expect(await _validVerificationTokens(pool, userId), hasLength(1));
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('invalid verification token returns generic bad request', () async {
    final pool = _pool();
    try {
      final response = await verify.onRequest(
        _withPool(
          TestRequestContext(
            path: '/api/v1/auth/verify-email',
            method: HttpMethod.post,
            body: jsonEncode({'token': 'invalid-token'}),
          ),
          pool,
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
    } finally {
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('middleware rejects token using another user session', () async {
    final pool = _pool();
    final ownerId = const Uuid().v4();
    final otherId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    try {
      await _insertUser(pool, ownerId);
      await _insertUser(pool, otherId);
      await _insertSession(pool, otherId, sessionId);
      final token = JwtUtils.generate(
        ownerId,
        tokenVersion: 0,
        sessionId: sessionId,
      );
      final request = TestRequestContext(
        path: '/api/v1/auth/me',
        method: HttpMethod.get,
        headers: {'authorization': 'Bearer $token'},
      );
      final response = await authMiddleware(
        (_) => Response(body: 'unexpected'),
      )(_withPool(request, pool));
      expect(response.statusCode, HttpStatus.unauthorized);
    } finally {
      await _deleteUser(pool, ownerId);
      await _deleteUser(pool, otherId);
      await pool.close();
    }
  }, skip: _skipDbTest);
}

const _mailEnvironment = <String, String>{
  'APP_BASE_URL': 'https://app.example.com',
  'SMTP_HOST': 'smtp.example.com',
  'SMTP_PORT': '587',
  'SMTP_USERNAME': 'mailer@example.com',
  'SMTP_PASSWORD': 'not-a-secret',
  'SMTP_FROM': 'mailer@example.com',
};

RequestContext _withPool(TestRequestContext request, Pool<dynamic> pool) {
  request.provide<Pool<dynamic>>(pool);
  return request.context;
}

Pool<dynamic> _pool() => Pool<dynamic>.withUrl(
  Uri.parse(Platform.environment['DATABASE_URL']!)
      .replace(
        queryParameters: {
          for (final entry in Uri.parse(
            Platform.environment['DATABASE_URL']!,
          ).queryParameters.entries)
            if (entry.key != 'channel_binding') entry.key: entry.value,
        },
      )
      .toString(),
);

bool get _skipDbTest =>
    Platform.environment['DATABASE_URL'] == null ||
    Platform.environment['JWT_SECRET'] == null;

Future<void> _insertUser(
  Pool<dynamic> pool,
  String userId, {
  bool verified = false,
}) => pool.execute(
  Sql.named('''INSERT INTO users (id, email, password_hash, email_verified_at)
    VALUES (@id, @email, @password_hash, @verified)'''),
  parameters: {
    'id': userId,
    'email': '$userId@example.com',
    'password_hash': PasswordUtils.hash('password123'),
    'verified': verified ? DateTime.now().toUtc() : null,
  },
);

Future<void> _insertSession(
  Pool<dynamic> pool,
  String userId,
  String sessionId,
) => pool.execute(
  Sql.named(
    '''INSERT INTO user_sessions
    (id, user_id, device_id, refresh_token_hash, expires_at)
    VALUES (@id, @user_id, 'email-test', 'hash', CURRENT_TIMESTAMP + INTERVAL '1 day')''',
  ),
  parameters: {'id': sessionId, 'user_id': userId},
);

Future<void> _deleteUser(Pool<dynamic> pool, String userId) => pool.execute(
  Sql.named('DELETE FROM users WHERE id = @id'),
  parameters: {'id': userId},
);

Future<List<ResultRow>> _validVerificationTokens(
  Pool<dynamic> pool,
  String userId,
) => pool.execute(
  Sql.named('''SELECT id FROM auth_tokens
    WHERE user_id = @user_id AND purpose = 'email_verification'
      AND used_at IS NULL AND expires_at > CURRENT_TIMESTAMP'''),
  parameters: {'user_id': userId},
);
