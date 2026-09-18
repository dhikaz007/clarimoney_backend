import 'dart:convert';

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
