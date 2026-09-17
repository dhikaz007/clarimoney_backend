import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Middleware _dbPoolHandler() {
  final dbUrl = Platform.environment['DATABASE_URL'];
  if (dbUrl == null || dbUrl.isEmpty) {
    throw StateError('DATABASE_URL is required');
  }

  final uri = Uri.parse(dbUrl);

  final pool = _createPool(uri);

  return (handler) =>
      (context) => handler(context.provide<Pool<dynamic>>(() => pool));
}

Pool<dynamic> _createPool(Uri uri) {
  return Pool<dynamic>.withEndpoints(
    [
      Endpoint(
        host: uri.host,
        port: uri.hasPort ? uri.port : 5432,
        database: uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : 'neondb',
        username: Uri.decodeComponent(uri.userInfo.split(':').first),
        password: uri.userInfo.contains(':')
            ? Uri.decodeComponent(
                uri.userInfo.substring(uri.userInfo.indexOf(':') + 1),
              )
            : '',
      ),
    ],
    settings: const PoolSettings(
      maxConnectionCount: 5,
      sslMode: SslMode.require,
    ),
  );
}

Handler middleware(Handler handler) {
  return handler.use(requestLogger()).use(_cors()).use(_dbPoolHandler());
}

Middleware _cors() {
  return (handler) => (context) async {
    final origin = context.request.headers['origin'];
    final allowed = Platform.environment['ALLOWED_ORIGIN'];
    final response = await handler(context);
    if (origin == null || allowed == null || origin != allowed) {
      return response;
    }
    return response.copyWith(
      headers: {
        ...response.headers,
        'access-control-allow-origin': origin,
        'access-control-allow-headers': 'Authorization, Content-Type',
        'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'vary': 'Origin',
      },
    );
  };
}
