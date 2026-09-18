import 'dart:convert';

import 'exact_decimal.dart';

Map<String, dynamic> decodeObject(Object? body) {
  if (body is! String)
    throw const FormatException('Request body must be an object');
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Request body must be an object');
  }
  return decoded;
}

String? trimmedNote(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid note');
  final note = value.trim();
  if (note.length > 500) throw const FormatException('Invalid note');
  return note.isEmpty ? null : note;
}

DateTime? fullIsoDate(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

String escapeLike(String value) =>
    value.replaceAllMapped(RegExp(r'[\\%_]'), (match) => '\\${match.group(0)}');

bool validUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

bool validTransactionAmount(num? value) =>
    value != null &&
    value > 0 &&
    value.isFinite &&
    !value.toString().contains('e') &&
    (value.toString().split('.').elementAtOrNull(1)?.length ?? 0) <= 2;

bool hasScientificAmountLiteral(String body) => RegExp(
  r'"amount"\s*:\s*[-+]?(?:\d+\.?\d*|\.\d+)[eE][+-]?\d+',
).hasMatch(body);

Object? comparisonJsonNumeric(Object? value) {
  return exactJsonDecimal(value);
}
