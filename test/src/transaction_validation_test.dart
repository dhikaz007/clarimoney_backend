import 'dart:convert';

import 'package:clarimoney_backend/src/transaction_validation.dart';
import 'package:test/test.dart';

void main() {
  test('rejects malformed and non-object JSON', () {
    expect(() => decodeObject('{'), throwsFormatException);
    expect(() => decodeObject(jsonEncode(['x'])), throwsFormatException);
    expect(() => decodeObject(jsonEncode('x')), throwsFormatException);
  });

  test('normalizes notes and rejects wrong types or long values', () {
    expect(trimmedNote('  '), isNull);
    expect(trimmedNote('  note  '), 'note');
    expect(() => trimmedNote(1), throwsFormatException);
    expect(() => trimmedNote('x' * 501), throwsFormatException);
  });

  test('requires timezone-bearing ISO datetime', () {
    expect(fullIsoDate('2026-09-15T08:30:00.000Z'), isNotNull);
    expect(fullIsoDate('2026-09-15 08:30:00'), isNull);
  });

  test('escapes LIKE wildcard characters', () {
    expect(escapeLike(r'100%_done\'), r'100\%\_done\\');
  });
}
