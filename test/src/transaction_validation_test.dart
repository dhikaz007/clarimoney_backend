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

  test('accepts only positive amounts with at most two decimal places', () {
    expect(validTransactionAmount(0.01), isTrue);
    expect(validTransactionAmount(9999999999999.99), isTrue);
    expect(validTransactionAmount(1.001), isFalse);
    expect(validTransactionAmount(0), isFalse);
    expect(validTransactionAmount(-1), isFalse);
  });

  test('rejects scientific amount literals before JSON numeric conversion', () {
    expect(hasScientificAmountLiteral('{"amount":1e2}'), isTrue);
    expect(hasScientificAmountLiteral('{"amount":1.00}'), isFalse);
  });

  test('validates UUID shape', () {
    expect(validUuid('00000000-0000-4000-8000-000000000001'), isTrue);
    expect(validUuid('not-a-uuid'), isFalse);
  });
}
