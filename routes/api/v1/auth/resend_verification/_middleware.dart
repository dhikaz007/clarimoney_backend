import 'package:clarimoney_backend/src/auth_middleware.dart';
import 'package:clarimoney_backend/src/services/email_service.dart';
import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) => authMiddleware(
  (context) => handler(context.provide<EmailService>(() => EmailService())),
);
