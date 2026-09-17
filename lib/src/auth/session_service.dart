import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../utils/jwt_utils.dart';
import '../utils/refresh_token_utils.dart';

class SessionService {
  SessionService(this._pool);

  static const refreshTokenLifetime = Duration(days: 30);
  final Pool<dynamic> _pool;
  final Uuid _uuid = const Uuid();

  Future<Map<String, String>> createSession({
    required String userId,
    required String deviceId,
    String? deviceName,
    String? userAgent,
  }) async {
    final sessionId = _uuid.v4();
    final refreshToken = RefreshTokenUtils.generate();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(refreshTokenLifetime);

    await _pool.runTx((session) async {
      // Device uniqueness means new login replaces prior device session.
      await session.execute(
        Sql.named('''
          INSERT INTO user_sessions
            (id, user_id, device_id, device_name, user_agent,
             refresh_token_hash, expires_at)
          VALUES (@id, @user_id, @device_id, @device_name, @user_agent,
                  @refresh_token_hash, @expires_at)
          ON CONFLICT (user_id, device_id) DO UPDATE SET
            id = EXCLUDED.id,
            device_name = EXCLUDED.device_name,
            user_agent = EXCLUDED.user_agent,
            refresh_token_hash = EXCLUDED.refresh_token_hash,
            created_at = CURRENT_TIMESTAMP,
            expires_at = EXCLUDED.expires_at,
            revoked_at = NULL,
            last_used_at = NULL
        '''),
        parameters: {
          'id': sessionId,
          'user_id': userId,
          'device_id': deviceId,
          'device_name': deviceName,
          'user_agent': userAgent,
          'refresh_token_hash': RefreshTokenUtils.hash(refreshToken),
          'expires_at': expiresAt,
        },
      );
    });

    return {
      'sessionId': sessionId,
      'accessToken': JwtUtils.generate(userId),
      'refreshToken': refreshToken,
    };
  }

  Future<Map<String, String>?> rotateRefreshToken(String refreshToken) {
    final tokenHash = RefreshTokenUtils.hash(refreshToken);
    final replacementToken = RefreshTokenUtils.generate();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(refreshTokenLifetime);

    return _pool.runTx((session) async {
      final result = await session.execute(
        Sql.named('''
          SELECT id, user_id, expires_at, revoked_at
          FROM user_sessions
          WHERE refresh_token_hash = @refresh_token_hash
          FOR UPDATE
        '''),
        parameters: {'refresh_token_hash': tokenHash},
      );
      if (result.isEmpty) return null;

      final row = result.first;
      final sessionId = row[0];
      final userId = row[1];
      final expires = row[2];
      final revokedAt = row[3];
      if (sessionId is! String ||
          userId is! String ||
          expires is! DateTime ||
          revokedAt != null) {
        if (sessionId is String && userId is String) {
          await _revoke(session, sessionId, userId);
        }
        return null;
      }
      if (!expires.toUtc().isAfter(now)) {
        await _revoke(session, sessionId, userId);
        return null;
      }

      await session.execute(
        Sql.named('''
          UPDATE user_sessions
          SET refresh_token_hash = @replacement_hash,
              expires_at = @expires_at,
              last_used_at = @last_used_at
          WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL
        '''),
        parameters: {
          'replacement_hash': RefreshTokenUtils.hash(replacementToken),
          'expires_at': expiresAt,
          'last_used_at': now,
          'id': sessionId,
          'user_id': userId,
        },
      );
      return {
        'accessToken': JwtUtils.generate(userId),
        'refreshToken': replacementToken,
      };
    });
  }

  Future<bool> revokeSession(String sessionId, String userId) async {
    final result = await _pool.execute(
      Sql.named('''
        UPDATE user_sessions SET revoked_at = CURRENT_TIMESTAMP
        WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL
      '''),
      parameters: {'id': sessionId, 'user_id': userId},
    );
    return result.affectedRows > 0;
  }

  Future<int> revokeAll(String userId) async {
    final result = await _pool.execute(
      Sql.named('''
        UPDATE user_sessions SET revoked_at = CURRENT_TIMESTAMP
        WHERE user_id = @user_id AND revoked_at IS NULL
      '''),
      parameters: {'user_id': userId},
    );
    return result.affectedRows;
  }

  Future<void> _revoke(Session session, String sessionId, String userId) async {
    await session.execute(
      Sql.named('''
        UPDATE user_sessions SET revoked_at = CURRENT_TIMESTAMP
        WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL
      '''),
      parameters: {'id': sessionId, 'user_id': userId},
    );
  }
}
