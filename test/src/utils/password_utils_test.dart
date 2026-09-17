import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordUtils', () {
    test('hashes password and verifies original value', () {
      final hash = PasswordUtils.hash('correct horse battery staple');

      expect(hash, isNot(equals('correct horse battery staple')));
      expect(
        PasswordUtils.verify('correct horse battery staple', hash),
        isTrue,
      );
      expect(PasswordUtils.verify('wrong password', hash), isFalse);
    });

    test('generates a different salted hash for same password', () {
      expect(
        PasswordUtils.hash('same password'),
        isNot(equals(PasswordUtils.hash('same password'))),
      );
    });
  });
}
