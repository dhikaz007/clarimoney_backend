import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../utils/auth_token_utils.dart';

class AuthTokenIssue {
  AuthTokenIssue({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;
}

class AuthTokenService {
  AuthTokenService(this._pool);
  final Pool<dynamic> _pool;
  final Uuid _uuid = const Uuid();

  Future<AuthTokenIssue> issue(
    String userId,
    String purpose,
    Duration lifetime,
  ) async {
    final token = AuthTokenUtils.generate();
    final expiresAt = DateTime.now().toUtc().add(lifetime);
    await _pool.execute(
      Sql.named('''INSERT INTO auth_tokens
        (id, user_id, token_hash, purpose, expires_at)
        VALUES (@id, @user_id, @token_hash, @purpose, @expires_at)'''),
      parameters: {
        'id': _uuid.v4(),
        'user_id': userId,
        'token_hash': AuthTokenUtils.hash(token),
        'purpose': purpose,
        'expires_at': expiresAt,
      },
    );
    return AuthTokenIssue(token: token, expiresAt: expiresAt);
  }

  Future<AuthTokenIssue> issueInTransaction(
    Session session,
    String userId,
    String purpose,
    Duration lifetime,
  ) async {
    final token = AuthTokenUtils.generate();
    final expiresAt = DateTime.now().toUtc().add(lifetime);
    await session.execute(
      Sql.named('''INSERT INTO auth_tokens
        (id, user_id, token_hash, purpose, expires_at)
        VALUES (@id, @user_id, @token_hash, @purpose, @expires_at)'''),
      parameters: {
        'id': _uuid.v4(),
        'user_id': userId,
        'token_hash': AuthTokenUtils.hash(token),
        'purpose': purpose,
        'expires_at': expiresAt,
      },
    );
    return AuthTokenIssue(token: token, expiresAt: expiresAt);
  }

  Future<String?> consume(String token, String purpose) async {
    final result = await _pool.runTx((session) async {
      final rows = await session.execute(
        Sql.named('''SELECT user_id FROM auth_tokens
          WHERE token_hash = @token_hash AND purpose = @purpose
            AND used_at IS NULL AND expires_at > CURRENT_TIMESTAMP
          FOR UPDATE'''),
        parameters: {
          'token_hash': AuthTokenUtils.hash(token),
          'purpose': purpose,
        },
      );
      if (rows.isEmpty || rows.first[0] is! String) return null;
      final update = await session.execute(
        Sql.named('''UPDATE auth_tokens SET used_at = CURRENT_TIMESTAMP
          WHERE token_hash = @token_hash AND used_at IS NULL'''),
        parameters: {'token_hash': AuthTokenUtils.hash(token)},
      );
      return update.affectedRows == 1 ? rows.first[0] as String : null;
    });
    return result;
  }
}
