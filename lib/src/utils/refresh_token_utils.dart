import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class RefreshTokenUtils {
  static String generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String hash(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }
}
