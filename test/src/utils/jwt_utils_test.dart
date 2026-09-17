import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:test/test.dart';

void main() {
  group('JwtUtils', () {
    setUp(() {});

    test('generates token and returns user ID when verified', () {
      final token = JwtUtils.generate('user-123');

      expect(JwtUtils.verify(token), equals('user-123'));
    });

    test('uses fifteen-minute expiry and preserves required claims', () {
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final claims = JwtUtils.verifyClaims(JwtUtils.generate('user-123'))!;
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      expect(claims['sub'], equals('user-123'));
      expect(claims['ver'], equals(0));
      expect(claims['exp'], inInclusiveRange(before + 899, after + 901));
    });

    test('returns null for malformed token', () {
      expect(JwtUtils.verify('not-a-token'), isNull);
    });
  });
}
