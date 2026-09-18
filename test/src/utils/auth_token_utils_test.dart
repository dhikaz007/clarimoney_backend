import 'package:clarimoney_backend/src/utils/auth_token_utils.dart';
import 'package:test/test.dart';

void main() {
  test('generates unique opaque tokens and stable SHA-256 hashes', () {
    final first = AuthTokenUtils.generate();
    final second = AuthTokenUtils.generate();
    expect(first, isNot(second));
    expect(AuthTokenUtils.hash(first), hasLength(64));
    expect(AuthTokenUtils.hash(first), AuthTokenUtils.hash(first));
    expect(AuthTokenUtils.hash(first), isNot(AuthTokenUtils.hash(second)));
  });
}
