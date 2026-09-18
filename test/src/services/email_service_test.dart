import 'dart:async';

import 'package:clarimoney_backend/src/services/email_service.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:test/test.dart';

void main() {
  test('rejects each missing SMTP configuration value', () async {
    const complete = {
      'APP_BASE_URL': 'https://app.example.com',
      'SMTP_HOST': 'smtp.example.com',
      'SMTP_PORT': '587',
      'SMTP_USERNAME': 'sender@example.com',
      'SMTP_PASSWORD': 'app-password',
      'SMTP_FROM': 'sender@example.com',
    };
    for (final key in complete.keys) {
      var sends = 0;
      final environment = {...complete}..remove(key);
      expect(
        () => EmailService(
          environment: environment,
          sender: (_, _) async => sends++,
        ).sendVerification(email: 'user@example.com', token: 'token'),
        throwsA(isA<EmailConfigurationException>()),
      );
      expect(sends, 0);
    }
  });

  test('rejects invalid SMTP port before sending', () async {
    var sends = 0;
    await expectLater(
      () => EmailService(
        environment: const {
          'APP_BASE_URL': 'https://app.example.com',
          'SMTP_HOST': 'smtp.example.com',
          'SMTP_PORT': 'not-a-port',
          'SMTP_USERNAME': 'sender@example.com',
          'SMTP_PASSWORD': 'app-password',
          'SMTP_FROM': 'sender@example.com',
        },
        sender: (_, _) async => sends++,
      ).sendVerification(email: 'user@example.com', token: 'token'),
      throwsA(isA<EmailConfigurationException>()),
    );
    expect(sends, 0);
  });

  test('builds verification message from configured values', () async {
    Message? captured;
    await EmailService(
      environment: const {
        'APP_BASE_URL': 'https://app.example.com',
        'SMTP_HOST': 'smtp.example.com',
        'SMTP_PORT': '587',
        'SMTP_USERNAME': 'sender@example.com',
        'SMTP_PASSWORD': 'app-password',
        'SMTP_FROM': 'sender@example.com',
      },
      sender: (message, _) async => captured = message,
    ).sendVerification(email: 'user@example.com', token: 'opaque-token');
    expect(captured?.subject, contains('Verify'));
    expect(captured?.recipients, contains('user@example.com'));
    expect(
      captured?.text,
      contains('https://app.example.com/verify-email?token=opaque-token'),
    );
  });

  test('converts SMTP failures to controlled errors', () async {
    expect(
      EmailService(
        environment: const {
          'APP_BASE_URL': 'https://app.example.com',
          'SMTP_HOST': 'smtp.example.com',
          'SMTP_PORT': '587',
          'SMTP_USERNAME': 'sender@example.com',
          'SMTP_PASSWORD': 'app-password',
          'SMTP_FROM': 'sender@example.com',
        },
        sender: (_, SmtpServer _) async => throw StateError('network'),
      ).sendPasswordReset(email: 'user@example.com', token: 'opaque-token'),
      throwsA(isA<EmailSendException>()),
    );
  });

  test('times out SMTP delivery with a controlled error', () async {
    expect(
      EmailService(
        environment: const {
          'APP_BASE_URL': 'https://app.example.com',
          'SMTP_HOST': 'smtp.example.com',
          'SMTP_PORT': '587',
          'SMTP_USERNAME': 'sender@example.com',
          'SMTP_PASSWORD': 'app-password',
          'SMTP_FROM': 'sender@example.com',
        },
        sender: (_, __) => Completer<void>().future,
      ).sendPasswordReset(email: 'user@example.com', token: 'opaque-token'),
      throwsA(isA<EmailSendTimeoutException>()),
    );
  });
}
