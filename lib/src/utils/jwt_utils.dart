import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class JwtUtils {
  static const accessTokenLifetime = Duration(minutes: 15);

  static String get _secret {
    final secret = Platform.environment['JWT_SECRET'];
    if (secret == null || secret.length < 32) {
      throw StateError('JWT_SECRET must contain at least 32 characters');
    }
    return secret;
  }

  static String generate(String userId, {int tokenVersion = 0}) {
    final jwt = JWT({
      'sub': userId,
      'ver': tokenVersion,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp':
          DateTime.now().add(accessTokenLifetime).millisecondsSinceEpoch ~/
          1000,
    });
    return jwt.sign(SecretKey(_secret));
  }

  static String? verify(String token) {
    final claims = verifyClaims(token);
    final subject = claims?['sub'];
    return subject is String ? subject : null;
  }

  static Map<String, dynamic>? verifyClaims(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secret));
      final payload = jwt.payload;
      return payload is Map<String, dynamic> ? payload : null;
    } catch (_) {
      return null;
    }
  }
}
