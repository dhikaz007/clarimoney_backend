import 'dart:convert';
import 'dart:io';

import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:clarimoney_backend/src/utils/auth_token_utils.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../routes/api/v1/auth/account/index.dart' as account;

void main() {
  test('deletes account and cascaded data after valid password', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      await _insertRelatedData(pool, userId);

      final response = await _delete(pool, userId, 'password123');

      expect(response.statusCode, HttpStatus.ok);
      expect(await _count(pool, 'users', userId), 0);
      expect(await _count(pool, 'categories', userId), 0);
      expect(await _count(pool, 'transactions', userId), 0);
      expect(await _count(pool, 'user_sessions', userId), 0);
      expect(await _count(pool, 'auth_tokens', userId), 0);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('wrong password returns 401 and preserves account data', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);

      final response = await _delete(pool, userId, 'wrong-password');

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(await _count(pool, 'users', userId), 1);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('missing password returns 401 and preserves account data', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);

      final response = await _deletePayload(pool, userId, {});

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(await _count(pool, 'users', userId), 1);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);
}

Future<Response> _delete(Pool<dynamic> pool, String userId, String password) =>
    _deletePayload(pool, userId, {'password': password});

Future<Response> _deletePayload(
  Pool<dynamic> pool,
  String userId,
  Map<String, Object?> payload,
) async {
  final sessionId = const Uuid().v4();
  final token = JwtUtils.generate(userId, sessionId: sessionId);
  final request = TestRequestContext(
    path: '/api/v1/auth/account',
    method: HttpMethod.delete,
    body: jsonEncode(payload),
    headers: {'authorization': 'Bearer $token'},
  );
  await pool.execute(
    Sql.named(
      '''INSERT INTO user_sessions
      (id, user_id, device_id, refresh_token_hash, expires_at)
      VALUES (@id, @user_id, @device_id, 'test-hash', CURRENT_TIMESTAMP + INTERVAL '1 day')''',
    ),
    parameters: {'id': sessionId, 'user_id': userId, 'device_id': sessionId},
  );
  request.provide<Pool<dynamic>>(pool);
  return account.onRequest(request.context);
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

bool get _skipDbTest => Platform.environment['DATABASE_URL'] == null;

Future<void> _insertUser(Pool<dynamic> pool, String userId) => pool.execute(
  Sql.named('''INSERT INTO users (id, email, password_hash)
        VALUES (@id, @email, @password_hash)'''),
  parameters: {
    'id': userId,
    'email': '$userId@example.com',
    'password_hash': PasswordUtils.hash('password123'),
  },
);

Future<void> _insertRelatedData(Pool<dynamic> pool, String userId) async {
  final categoryId = const Uuid().v4();
  final sessionId = const Uuid().v4();
  await pool.execute(
    Sql.named('''INSERT INTO categories (id, user_id, name, type)
      VALUES (@id, @user_id, 'Test', 'expense')'''),
    parameters: {'id': categoryId, 'user_id': userId},
  );
  await pool.execute(
    Sql.named('''INSERT INTO transactions
      (id, user_id, category_id, amount, date)
      VALUES (@id, @user_id, @category_id, 1.00, CURRENT_TIMESTAMP)'''),
    parameters: {
      'id': const Uuid().v4(),
      'user_id': userId,
      'category_id': categoryId,
    },
  );
  await pool.execute(
    Sql.named(
      '''INSERT INTO user_sessions
      (id, user_id, device_id, refresh_token_hash, expires_at)
      VALUES (@id, @user_id, @device_id, @hash, CURRENT_TIMESTAMP + INTERVAL '1 day')''',
    ),
    parameters: {
      'id': sessionId,
      'user_id': userId,
      'device_id': sessionId,
      'hash': 'test-hash',
    },
  );
  await pool.execute(
    Sql.named(
      '''INSERT INTO auth_tokens
      (id, user_id, token_hash, purpose, expires_at)
      VALUES (@id, @user_id, @hash, 'password_reset', CURRENT_TIMESTAMP + INTERVAL '1 day')''',
    ),
    parameters: {
      'id': const Uuid().v4(),
      'user_id': userId,
      'hash': AuthTokenUtils.hash(AuthTokenUtils.generate()),
    },
  );
}

Future<int> _count(Pool<dynamic> pool, String table, String userId) async {
  final rows = await pool.execute(
    Sql.named('SELECT COUNT(*) FROM $table WHERE user_id = @id'),
    parameters: {'id': userId},
  );
  return rows.single[0] as int;
}

Future<void> _deleteUser(Pool<dynamic> pool, String userId) => pool.execute(
  Sql.named('DELETE FROM users WHERE id = @id'),
  parameters: {'id': userId},
);
