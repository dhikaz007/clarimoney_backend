import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class AuthTokenUtils {
  static String generate() => base64Url
      .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');

  static String hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}
