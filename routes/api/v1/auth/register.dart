import 'dart:async';
import 'dart:io';
import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
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

    if (email == null ||
        password == null ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        password.length < 8) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Valid email and password of at least 8 characters required',
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

    await pool.execute(
      Sql.named('''
        INSERT INTO users (id, email, password_hash) 
        VALUES (@id, @email, @hash)
      '''),
      parameters: {'id': id, 'email': email, 'hash': hash},
    );

    final token = JwtUtils.generate(id);

    return apiResponse(
      statusCode: HttpStatus.created,
      message: 'Registration successful',
      data: {
        'user': {'id': id, 'email': email},
        'token': token,
      },
    );
  } catch (e) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Registration failed',
    );
  }
}
