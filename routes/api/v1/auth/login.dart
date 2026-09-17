import 'dart:async';
import 'dart:io';
import 'package:clarimoney_backend/src/utils/jwt_utils.dart';
import 'package:clarimoney_backend/src/utils/password_utils.dart';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

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

    if (email == null || password == null) {
      return apiResponse(
        statusCode: HttpStatus.badRequest,
        message: 'Email and password required',
      );
    }

    final pool = context.read<Pool<dynamic>>();

    final result = await pool.execute(
      Sql.named(
        'SELECT id, password_hash, token_version FROM users WHERE email = @email',
      ),
      parameters: {'email': email},
    );

    if (result.isEmpty) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid email or password',
      );
    }

    final row = result.first;
    final id = row[0];
    final hash = row[1];
    final tokenVersion = row[2];
    if (id is! String || hash is! String || tokenVersion is! int) {
      return apiResponse(
        statusCode: HttpStatus.internalServerError,
        message: 'Invalid user record',
      );
    }

    if (!PasswordUtils.verify(password, hash)) {
      return apiResponse(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid email or password',
      );
    }

    final token = JwtUtils.generate(id, tokenVersion: tokenVersion);

    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Login successful',
      data: {
        'user': {'id': id, 'email': email},
        'token': token,
      },
    );
  } catch (e) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Login failed',
    );
  }
}
