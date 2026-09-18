import 'package:clarimoney_backend/src/services/email_service.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:test/test.dart';

void main() {
  test('rejects missing SMTP configuration', () async {
    expect(
      () => EmailService(
        environment: const {},
      ).sendVerification(email: 'user@example.com', token: 'token'),
      throwsA(isA<EmailConfigurationException>()),
    );
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
}
