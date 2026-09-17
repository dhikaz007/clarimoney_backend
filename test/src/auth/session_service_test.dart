import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:test/test.dart';

void main() {
  test('refresh lifetime remains bounded', () {
    expect(SessionService.refreshTokenLifetime, const Duration(days: 30));
  });
}
