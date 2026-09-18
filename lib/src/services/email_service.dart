import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

typedef MailSender = Future<void> Function(Message message, SmtpServer server);

class EmailConfigurationException implements Exception {
  EmailConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EmailSendException implements Exception {
  EmailSendException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EmailService {
  EmailService({Map<String, String>? environment, MailSender? sender})
    : _environment = environment ?? Platform.environment,
      _sender = sender ?? _send;

  final Map<String, String> _environment;
  final MailSender _sender;

  void validateConfiguration() {
    _config();
    final base = _environment['APP_BASE_URL'];
    if (base == null || base.trim().isEmpty) {
      throw EmailConfigurationException('APP_BASE_URL is not configured');
    }
  }

  Future<void> sendVerification({
    required String email,
    required String token,
  }) => _sendLink(
    email,
    'Verify your ClariMoney email',
    '/verify-email',
    token,
    'Verify your email address',
  );

  Future<void> sendPasswordReset({
    required String email,
    required String token,
  }) => _sendLink(
    email,
    'Reset your ClariMoney password',
    '/reset-password',
    token,
    'Reset your password',
  );

  Future<void> _sendLink(
    String email,
    String subject,
    String path,
    String token,
    String heading,
  ) async {
    validateConfiguration();
    final config = _config();
    final base = _environment['APP_BASE_URL']!;
    final link = '${base.replaceFirst(RegExp(r'\/$'), '')}$path?token=$token';
    final message = Message()
      ..from = config.from
      ..recipients.add(email)
      ..subject = subject
      ..text = '$heading:\n$link';
    try {
      await _sender(message, config.server);
    } catch (_) {
      throw EmailSendException('Unable to send email');
    }
  }

  _EmailConfig _config() {
    String required(String key) {
      final value = _environment[key];
      if (value == null || value.trim().isEmpty) {
        throw EmailConfigurationException('$key is not configured');
      }
      return value;
    }

    final port = int.tryParse(required('SMTP_PORT'));
    if (port == null || port < 1 || port > 65535) {
      throw EmailConfigurationException('SMTP_PORT is invalid');
    }
    final username = required('SMTP_USERNAME');
    return _EmailConfig(
      from: required('SMTP_FROM'),
      server: SmtpServer(
        required('SMTP_HOST'),
        port: port,
        username: username,
        password: required('SMTP_PASSWORD'),
      ),
    );
  }

  static Future<void> _send(Message message, SmtpServer server) async {
    await send(message, server);
  }
}

class _EmailConfig {
  _EmailConfig({required this.from, required this.server});
  final String from;
  final SmtpServer server;
}
