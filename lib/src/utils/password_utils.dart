import 'package:crypt/crypt.dart';

class PasswordUtils {
  static String hash(String password) {
    return Crypt.sha512(password).toString();
  }

  static bool verify(String password, String hashed) {
    return Crypt(hashed).match(password);
  }
}
