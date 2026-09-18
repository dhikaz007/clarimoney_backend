import 'dart:io';

import 'package:postgres/postgres.dart';

Pool<dynamic> testPool() {
  final raw = Platform.environment['DATABASE_URL'];
  if (raw == null) throw StateError('DATABASE_URL is required');
  final url = Uri.parse(raw);
  return Pool<dynamic>.withUrl(
    url.replace(
      queryParameters: {
        for (final entry in url.queryParameters.entries)
          if (entry.key != 'channel_binding') entry.key: entry.value,
      },
    ).toString(),
  );
}
