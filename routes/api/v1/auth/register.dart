import 'dart:async';
import 'dart:io';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:clarimoney_backend/src/auth/session_service.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';
import 'package:clarimoney_backend/src/api_response.dart';

FutureOr<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final email = (body['email'] as String?)?.trim().toLowerCase();
    final password = body['password'] as String?;
    final deviceId = body['device_id'] is String
        ? (body['device_id'] as String).trim()
        : null;
    final deviceName = body['device_name'] is String
        ? (body['device_name'] as String).trim()
        : null;

    if (email == null ||
        password == null ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        password.length < 8) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Valid email and password of at least 8 characters required',
      );
    }
    if (deviceId == null || deviceId.isEmpty || deviceId.length > 255) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message:
            'device_id must be a non-empty string of 255 characters or fewer',
      );
    }
    if (body.containsKey('device_name') && body['device_name'] is! String) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'device_name must be a string',
      );
    }
    if (deviceName != null && deviceName.runes.length > 255) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'device_name must be 255 characters or fewer',
      );
    }

    final pool = context.read<Pool<dynamic>>();

    final existing = await pool.execute(
      Sql.named('SELECT id FROM users WHERE email = @email'),
      parameters: {'email': email},
    );

    if (existing.isNotEmpty) {
      return apiResponse(
        statusCode: HttpStatus.conflict,
        message: 'Email already registered',
      );
    }

    final id = const Uuid().v4();
    final hash = PasswordUtils.hash(password);

    final session = await pool.runTx((transaction) async {
      await transaction.execute(
        Sql.named('''
          INSERT INTO users (id, email, password_hash) 
          VALUES (@id, @email, @hash)
        '''),
        parameters: {'id': id, 'email': email, 'hash': hash},
      );
      return SessionService(pool).createSessionInTransaction(
        transaction,
        userId: id,
        deviceId: deviceId,
        deviceName: deviceName,
        userAgent: context.request.headers['user-agent'],
      );
    });

    return apiResponse(
      statusCode: HttpStatus.created,
      message: 'Registration successful',
      data: {
        'user': {'id': id, 'email': email, 'email_verified': false},
        'access_token': session['accessToken'],
        'refresh_token': session['refreshToken'],
        'session_id': session['sessionId'],
        'token': session['accessToken'],
      },
    );
  } catch (e) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Registration failed',
    );
  }
}
