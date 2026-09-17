import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:test/test.dart';

void main() {
  group('JwtUtils', () {
    setUp(() {});

    test('generates token and returns user ID when verified', () {
      final token = JwtUtils.generate('user-123');

      expect(JwtUtils.verify(token), equals('user-123'));
    });

    test('returns null for malformed token', () {
      expect(JwtUtils.verify('not-a-token'), isNull);
    });
  });
}
