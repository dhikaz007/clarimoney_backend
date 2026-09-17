import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../utils/jwt_utils.dart';
import '../utils/refresh_token_utils.dart';

class SessionService {
  SessionService(
    this._pool, {
    String Function(String userId)? accessTokenGenerator,
  }) : _accessTokenGenerator = accessTokenGenerator ?? JwtUtils.generate;

  static const refreshTokenLifetime = Duration(days: 30);
  final Pool<dynamic> _pool;
  final String Function(String userId) _accessTokenGenerator;
  final Uuid _uuid = const Uuid();

  Future<Map<String, String>> createSession({
    required String userId,
    required String deviceId,
    String? deviceName,
    String? userAgent,
  }) {
    return _pool.runTx(
      (session) => createSessionInTransaction(
        session,
        userId: userId,
        deviceId: deviceId,
        deviceName: deviceName,
        userAgent: userAgent,
      ),
    );
  }

  Future<Map<String, String>> createSessionInTransaction(
    Session session, {
    required String userId,
    required String deviceId,
    String? deviceName,
    String? userAgent,
  }) async {
    final sessionId = _uuid.v4();
    final refreshToken = RefreshTokenUtils.generate();
    final accessToken = _accessTokenGenerator(userId);
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(refreshTokenLifetime);
    late String persistedSessionId;

    // Device uniqueness means new login replaces prior device session.
    final result = await session.execute(
      Sql.named('''
          INSERT INTO user_sessions
            (id, user_id, device_id, device_name, user_agent,
             refresh_token_hash, expires_at)
          VALUES (@id, @user_id, @device_id, @device_name, @user_agent,
                  @refresh_token_hash, @expires_at)
          ON CONFLICT (user_id, device_id) DO UPDATE SET
            device_name = EXCLUDED.device_name,
            user_agent = EXCLUDED.user_agent,
            refresh_token_hash = EXCLUDED.refresh_token_hash,
            created_at = CURRENT_TIMESTAMP,
            expires_at = EXCLUDED.expires_at,
            revoked_at = NULL,
            last_used_at = NULL
          RETURNING id
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
    if (result.isEmpty || result.first[0] is! String) {
      throw StateError('Session insert failed');
    }
    persistedSessionId = result.first[0] as String;
    await session.execute(
      Sql.named('''
          UPDATE refresh_token_history
          SET consumed_at = COALESCE(consumed_at, @consumed_at)
          WHERE session_id = @session_id AND consumed_at IS NULL
        '''),
      parameters: {'consumed_at': now, 'session_id': persistedSessionId},
    );
    await session.execute(
      Sql.named('''
          INSERT INTO refresh_token_history (token_hash, session_id, expires_at)
          VALUES (@token_hash, @session_id, @expires_at)
        '''),
      parameters: {
        'token_hash': RefreshTokenUtils.hash(refreshToken),
        'session_id': persistedSessionId,
        'expires_at': expiresAt,
      },
    );

    return {
      'sessionId': persistedSessionId,
      'accessToken': accessToken,
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
          SELECT h.session_id, s.user_id, h.expires_at, h.consumed_at,
                 s.expires_at, s.revoked_at
          FROM refresh_token_history h
          JOIN user_sessions s ON s.id = h.session_id
          WHERE h.token_hash = @refresh_token_hash
          FOR UPDATE
        '''),
        parameters: {'refresh_token_hash': tokenHash},
      );
      if (result.isEmpty) return null;

      final row = result.first;
      final sessionId = row[0];
      final userId = row[1];
      final tokenExpires = row[2];
      final consumedAt = row[3];
      final sessionExpires = row[4];
      final revokedAt = row[5];
      if (sessionId is! String ||
          userId is! String ||
          tokenExpires is! DateTime ||
          sessionExpires is! DateTime) {
        if (sessionId is String && userId is String) {
          await _revoke(session, sessionId, userId);
        }
        return null;
      }
      if (consumedAt != null || revokedAt != null) {
        await _revoke(session, sessionId, userId);
        return null;
      }
      if (!tokenExpires.toUtc().isAfter(now) ||
          !sessionExpires.toUtc().isAfter(now)) {
        await _revoke(session, sessionId, userId);
        return null;
      }

      final accessToken = _accessTokenGenerator(userId);
      final update = await session.execute(
        Sql.named('''
          UPDATE user_sessions
          SET refresh_token_hash = @replacement_hash,
              expires_at = @expires_at,
              last_used_at = @last_used_at
          WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL
          RETURNING id
        '''),
        parameters: {
          'replacement_hash': RefreshTokenUtils.hash(replacementToken),
          'expires_at': expiresAt,
          'last_used_at': now,
          'id': sessionId,
          'user_id': userId,
        },
      );
      if (update.isEmpty) {
        await _revoke(session, sessionId, userId);
        return null;
      }
      final consumed = await session.execute(
        Sql.named('''
          UPDATE refresh_token_history
          SET consumed_at = @consumed_at
          WHERE token_hash = @token_hash AND consumed_at IS NULL
        '''),
        parameters: {'consumed_at': now, 'token_hash': tokenHash},
      );
      if (consumed.affectedRows != 1) {
        await _revoke(session, sessionId, userId);
        return null;
      }
      await session.execute(
        Sql.named('''
          INSERT INTO refresh_token_history (token_hash, session_id, expires_at)
          VALUES (@token_hash, @session_id, @expires_at)
        '''),
        parameters: {
          'token_hash': RefreshTokenUtils.hash(replacementToken),
          'session_id': sessionId,
          'expires_at': expiresAt,
        },
      );
      return {'accessToken': accessToken, 'refreshToken': replacementToken};
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
