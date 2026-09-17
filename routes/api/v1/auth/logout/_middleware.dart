import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) =>
    authMiddleware(handler, allowRevokedSession: true);
