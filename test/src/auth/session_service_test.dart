import 'dart:io';

import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('refresh lifetime remains bounded', () {
    expect(SessionService.refreshTokenLifetime, const Duration(days: 30));
  });

  test(
    'reused refresh token revokes current session',
    () async {
      final databaseUrl = Uri.parse(Platform.environment['DATABASE_URL']!);
      final pool = Pool<dynamic>.withUrl(
        databaseUrl
            .replace(
              queryParameters: {
                for (final entry in databaseUrl.queryParameters.entries)
                  if (entry.key != 'channel_binding') entry.key: entry.value,
              },
            )
            .toString(),
      );
      final userId = const Uuid().v4();
      try {
        await pool.execute(
          Sql.named(
            'INSERT INTO users (id, email, password_hash) VALUES (@id, @email, @password_hash)',
          ),
          parameters: {
            'id': userId,
            'email': '$userId@example.com',
            'password_hash': 'test',
          },
        );
        final service = SessionService(pool);
        final created = await service.createSession(
          userId: userId,
          deviceId: userId,
        );
        final rotated = await service.rotateRefreshToken(
          created['refreshToken']!,
        );

        expect(rotated, isNotNull);
        expect(
          await service.rotateRefreshToken(created['refreshToken']!),
          isNull,
        );
        final session = await pool.execute(
          Sql.named('SELECT revoked_at FROM user_sessions WHERE id = @id'),
          parameters: {'id': created['sessionId']},
        );
        expect(session.single[0], isNotNull);
      } finally {
        await pool.execute(
          Sql.named('DELETE FROM users WHERE id = @id'),
          parameters: {'id': userId},
        );
        await pool.close();
      }
    },
    skip:
        Platform.environment['DATABASE_URL'] == null ||
        Platform.environment['JWT_SECRET'] == null,
  );

  test('concurrent reuse revokes session after one rotation', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      final service = SessionService(pool);
      final created = await service.createSession(
        userId: userId,
        deviceId: userId,
      );
      final results = await Future.wait([
        service.rotateRefreshToken(created['refreshToken']!),
        service.rotateRefreshToken(created['refreshToken']!),
      ]);

      expect(results.whereType<Map<String, String>>(), hasLength(1));
      final current = await pool.execute(
        Sql.named('SELECT revoked_at FROM user_sessions WHERE id = @id'),
        parameters: {'id': created['sessionId']},
      );
      expect(current.single[0], isNotNull);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('JWT configuration failure rolls back session creation', () async {
    final pool = _pool();
    final userId = const Uuid().v4();
    try {
      await _insertUser(pool, userId);
      final service = SessionService(
        pool,
        accessTokenGenerator: (_) => throw StateError('invalid JWT config'),
      );

      expect(
        service.createSession(userId: userId, deviceId: userId),
        throwsStateError,
      );
      final sessions = await pool.execute(
        Sql.named('SELECT id FROM user_sessions WHERE user_id = @user_id'),
        parameters: {'user_id': userId},
      );
      expect(sessions, isEmpty);
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

Future<void> _insertUser(Pool<dynamic> pool, String userId) => pool.execute(
  Sql.named(
    'INSERT INTO users (id, email, password_hash) VALUES (@id, @email, @password_hash)',
  ),
  parameters: {
    'id': userId,
    'email': '$userId@example.com',
    'password_hash': 'test',
  },
);

Future<void> _deleteUser(Pool<dynamic> pool, String userId) => pool.execute(
  Sql.named('DELETE FROM users WHERE id = @id'),
  parameters: {'id': userId},
);

bool get _skipDbTest =>
    Platform.environment['DATABASE_URL'] == null ||
    Platform.environment['JWT_SECRET'] == null;
