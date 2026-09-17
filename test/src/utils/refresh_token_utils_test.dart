import 'package:clarimoney_backend/src/utils/refresh_token_utils.dart';
import 'package:test/test.dart';

void main() {
  group('RefreshTokenUtils', () {
    test('generates different opaque tokens', () {
      final first = RefreshTokenUtils.generate();
      final second = RefreshTokenUtils.generate();

      expect(first, isNot(equals(second)));
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(first.length, equals(43));
    });

    test('returns stable SHA-256 hex digest', () {
      expect(
        RefreshTokenUtils.hash('refresh-token'),
        equals(
          '0eb17643d4e9261163783a420859c92c7d212fa9624106a12b510afbec266120',
        ),
      );
    });
  });
}
