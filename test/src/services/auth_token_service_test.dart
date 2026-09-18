import 'dart:io';

import 'package:clarimoney_backend/src/services/auth_token_service.dart';
import 'package:clarimoney_backend/src/utils/auth_token_utils.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'issue persists only token hash and returns raw token with expiry',
    () async {
      final pool = _pool();
      final userId = await _insertUser(pool);
      try {
        final issued = await AuthTokenService(
          pool,
        ).issue(userId, 'email_verification', const Duration(hours: 1));
        final rows = await pool.execute(
          Sql.named(
            'SELECT token_hash, expires_at FROM auth_tokens WHERE user_id = @user_id',
          ),
          parameters: {'user_id': userId},
        );
        expect(issued.token, isNotEmpty);
        expect(issued.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
        expect(rows.single[0], AuthTokenUtils.hash(issued.token));
        expect(rows.single[0], isNot(issued.token));
        expect(rows.single[1], isA<DateTime>());
      } finally {
        await _deleteUser(pool, userId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test(
    'consume succeeds once, then rejects used and wrong-purpose tokens',
    () async {
      final pool = _pool();
      final userId = await _insertUser(pool);
      try {
        final service = AuthTokenService(pool);
        final issued = await service.issue(
          userId,
          'email_verification',
          const Duration(hours: 1),
        );
        expect(
          await service.consume(issued.token, 'email_verification'),
          userId,
        );
        expect(
          await service.consume(issued.token, 'email_verification'),
          isNull,
        );

        final other = await service.issue(
          userId,
          'password_reset',
          const Duration(hours: 1),
        );
        expect(
          await service.consume(other.token, 'email_verification'),
          isNull,
        );
        expect(await service.consume(other.token, 'password_reset'), userId);
      } finally {
        await _deleteUser(pool, userId);
        await pool.close();
      }
    },
    skip: _skipDbTest,
  );

  test('consume rejects expired token', () async {
    final pool = _pool();
    final userId = await _insertUser(pool);
    try {
      final service = AuthTokenService(pool);
      final issued = await service.issue(
        userId,
        'email_verification',
        const Duration(seconds: -1),
      );
      expect(await service.consume(issued.token, 'email_verification'), isNull);
    } finally {
      await _deleteUser(pool, userId);
      await pool.close();
    }
  }, skip: _skipDbTest);

  test('concurrent consume allows one caller', () async {
    final pool = _pool();
    final userId = await _insertUser(pool);
    try {
      final service = AuthTokenService(pool);
      final issued = await service.issue(
        userId,
        'email_verification',
        const Duration(hours: 1),
      );
      final results = await Future.wait([
        service.consume(issued.token, 'email_verification'),
        service.consume(issued.token, 'email_verification'),
      ]);
      expect(results.whereType<String>(), [userId]);
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

Future<String> _insertUser(Pool<dynamic> pool) async {
  final id = const Uuid().v4();
  await pool.execute(
    Sql.named(
      'INSERT INTO users (id, email, password_hash) VALUES (@id, @email, @password_hash)',
    ),
    parameters: {'id': id, 'email': '$id@example.com', 'password_hash': 'test'},
  );
  return id;
}

Future<void> _deleteUser(Pool<dynamic> pool, String id) => pool.execute(
  Sql.named('DELETE FROM users WHERE id = @id'),
  parameters: {'id': id},
);

bool get _skipDbTest =>
    Platform.environment['DATABASE_URL'] == null ||
    Platform.environment['JWT_SECRET'] == null;
