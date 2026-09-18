import 'dart:convert';
import 'dart:io';

import 'package:clarimoney_backend/src/services/email_service.dart';
import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:clarimoney_backend/src/utils/auth_token_utils.dart';
import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../routes/api/v1/auth/forgot_password.dart' as forgot;
import '../../routes/api/v1/auth/reset_password.dart' as reset;

void main() {
  test(
    'forgot password response does not reveal account existence',
    () async {
      final pool = _pool();
      final userId = const Uuid().v4();
      try {
        await _insertUser(pool, userId);
        final existing = await _forgot(pool, '$userId@example.com');
        final missing = await _forgot(pool, 'missing-$userId@example.com');
        expect(existing.statusCode, HttpStatus.ok);
        expect(missing.statusCode, HttpStatus.ok);
        expect(await existing.json(), await missing.json());
      } finally {
        await _deleteUser(pool, userId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test(
    'forgot password normalizes email and waits minimum duration',
    () async {
      final pool = _pool();
      final userId = const Uuid().v4();
      try {
        await _insertUser(pool, userId, email: 'user-$userId@example.com');
        final started = DateTime.now();
        final response = await _forgot(pool, ' USER-$userId@EXAMPLE.com ');
        final elapsed = DateTime.now().difference(started);
        expect(response.statusCode, HttpStatus.ok);
        expect(
          elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 250)),
        );
        expect(await _activeTokens(pool, userId), hasLength(1));
      } finally {
        await _deleteUser(pool, userId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test('SMTP failure rolls back reset token issuance', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      final response = await _forgot(
        pool,
        '$userId@example.com',
        sender: (_, __) => Future<void>.error(StateError('SMTP down')),
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(await _activeTokens(pool, userId), isEmpty);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('new forgot request invalidates prior reset token', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await _insertToken(pool, userId, AuthTokenUtils.generate());
      await _forgot(pool, '$userId@example.com');
      final used = await pool.execute(
        Sql.named(
          '''SELECT COUNT(*) FROM auth_tokens
          WHERE user_id = @id AND purpose = 'password_reset' AND used_at IS NOT NULL''',
        ),
        parameters: {'id': userId},
      );
      expect(used.single[0], 1);
      expect(await _activeTokens(pool, userId), hasLength(1));
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('reset succeeds once and revokes every session', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    final raw = AuthTokenUtils.generate();
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      await _insertToken(pool, userId, raw);
      final response = await _reset(pool, raw, 'newpassword');
      final reused = await _reset(pool, raw, 'anotherpass');
      final state = await pool.execute(
        Sql.named(
          '''SELECT password_hash, token_version FROM users WHERE id = @id''',
        ),
        parameters: {'id': userId},
      );
      final sessions = await pool.execute(
        Sql.named('SELECT revoked_at FROM user_sessions WHERE id = @id'),
        parameters: {'id': sessionId},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(reused.statusCode, HttpStatus.badRequest);
      expect(
        PasswordUtils.verify('newpassword', state.single[0] as String),
        isTrue,
      );
      expect(state.single[1], 1);
      expect(sessions.single[0], isNotNull);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test(
    'expired token and weak password return same generic failure',
    () async {
      final pool = _pool();
      final userId = const Uuid().v4();
      final expired = AuthTokenUtils.generate();
      try {
        await _insertUser(pool, userId);
        await _insertToken(pool, userId, expired, expired: true);
        final expiry = await _reset(pool, expired, 'password123');
        final weak = await _reset(pool, 'not-a-real-token', 'short');
        expect(expiry.statusCode, HttpStatus.badRequest);
        expect(weak.statusCode, HttpStatus.badRequest);
        expect(await expiry.json(), await weak.json());
      } finally {
        await _deleteUser(pool, userId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test('wrong-purpose token fails without consumption', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final raw = AuthTokenUtils.generate();
    try {
      await _insertUser(pool, userId);
      await pool.execute(
        Sql.named(
          '''INSERT INTO auth_tokens
          (id, user_id, token_hash, purpose, expires_at)
          VALUES (@id, @user_id, @hash, 'email_verification', CURRENT_TIMESTAMP + INTERVAL '30 minutes')''',
        ),
        parameters: {
          'id': const Uuid().v4(),
          'user_id': userId,
          'hash': AuthTokenUtils.hash(raw),
        },
      );
      final response = await _reset(pool, raw, 'newpassword');
      expect(response.statusCode, HttpStatus.badRequest);
      expect(await _activeTokens(pool, userId), isEmpty);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('reset token lifetime is 30 minutes', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await _forgot(pool, '$userId@example.com');
      final lifetime = await pool.execute(
        Sql.named(
          '''SELECT EXTRACT(EPOCH FROM (expires_at - created_at))
          FROM auth_tokens WHERE user_id = @id AND purpose = 'password_reset' ''',
        ),
        parameters: {'id': userId},
      );
      expect(double.parse(lifetime.single[0].toString()), closeTo(1800, 2));
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('reset token version rejects old access token', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final sessionId = const Uuid().v4();
    final raw = AuthTokenUtils.generate();
    try {
      await _insertUser(pool, userId);
      await _insertSession(pool, userId, sessionId);
      await _insertToken(pool, userId, raw);
      final oldAccessToken = JwtUtils.generate(userId, sessionId: sessionId);
      await _reset(pool, raw, 'newpassword');
      final request = TestRequestContext(
        path: '/api/v1/auth/me',
        headers: {'authorization': 'Bearer $oldAccessToken'},
      );
      request.provide<Pool<dynamic>>(pool);
      final response = await authMiddleware(
        (_) => Response(body: 'unexpected'),
      )(request.context);
      expect(response.statusCode, HttpStatus.unauthorized);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);
}

Future<Response> _forgot(
  Pool<dynamic> pool,
  String email, {
  MailSender? sender,
}) {
  final request = TestRequestContext(
    path: '/api/v1/auth/forgot-password',
    method: HttpMethod.post,
    body: jsonEncode({'email': email}),
  );
  request.provide<EmailService>(
    EmailService(
      environment: _mailEnvironment,
      sender: sender ?? (_, __) async {},
    ),
  );
  request.provide<Pool<dynamic>>(pool);
  return forgot.onRequest(request.context);
}

Future<Response> _reset(Pool<dynamic> pool, String token, String password) {
  final request = TestRequestContext(
    path: '/api/v1/auth/reset-password',
    method: HttpMethod.post,
    body: jsonEncode({'token': token, 'password': password}),
  );
  request.provide<Pool<dynamic>>(pool);
  return reset.onRequest(request.context);
}

const _mailEnvironment = <String, String>{
  'APP_BASE_URL': 'https://app.example.com',
  'SMTP_HOST': 'smtp.example.com',
  'SMTP_PORT': '587',
  'SMTP_USERNAME': 'mailer@example.com',
  'SMTP_PASSWORD': 'test-only',
  'SMTP_FROM': 'mailer@example.com',
};

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

bool get _skipDbTest => Platform.environment['DATABASE_URL'] == null;

Future<void> _insertUser(Pool<dynamic> pool, String userId, {String? email}) =>
    pool.execute(
      Sql.named('''INSERT INTO users (id, email, password_hash)
    VALUES (@id, @email, @password_hash)'''),
      parameters: {
        'id': userId,
        'email': email ?? '$userId@example.com',
        'password_hash': PasswordUtils.hash('password123'),
      },
    );

Future<void> _insertSession(Pool<dynamic> pool, String userId, String id) =>
    pool.execute(
      Sql.named(
        '''INSERT INTO user_sessions
    (id, user_id, device_id, refresh_token_hash, expires_at)
    VALUES (@id, @user_id, @device_id, 'test-hash', CURRENT_TIMESTAMP + INTERVAL '1 day')''',
      ),
      parameters: {'id': id, 'user_id': userId, 'device_id': id},
    );

Future<void> _insertToken(
  Pool<dynamic> pool,
  String userId,
  String token, {
  bool expired = false,
}) => pool.execute(
  Sql.named('''INSERT INTO auth_tokens
    (id, user_id, token_hash, purpose, expires_at)
    VALUES (@id, @user_id, @hash, 'password_reset',
      CURRENT_TIMESTAMP + (@duration)::interval)'''),
  parameters: {
    'id': const Uuid().v4(),
    'user_id': userId,
    'hash': AuthTokenUtils.hash(token),
    'duration': expired ? '-1 minute' : '30 minutes',
  },
);

Future<void> _deleteUser(Pool<dynamic> pool, String userId) => pool.execute(
  Sql.named('DELETE FROM users WHERE id = @id'),
  parameters: {'id': userId},
);

Future<List<ResultRow>> _activeTokens(Pool<dynamic> pool, String userId) =>
    pool.execute(
      Sql.named('''SELECT id FROM auth_tokens
        WHERE user_id = @id AND purpose = 'password_reset'
          AND used_at IS NULL AND expires_at > CURRENT_TIMESTAMP'''),
      parameters: {'id': userId},
    );
