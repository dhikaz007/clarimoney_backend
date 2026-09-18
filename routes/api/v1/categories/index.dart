import 'dart:async';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/transaction_validation.dart';

FutureOr<Response> onRequest(RequestContext context) async {
  final method = context.request.method;

  if (method == HttpMethod.get) {
    final userId = context.read<String>();
    final pool = context.read<Pool<dynamic>>();
    try {
      final result = await pool.execute(
        Sql.named('''
           SELECT id, name, icon, color, type, status, origin
          FROM categories
          WHERE user_id = @userId OR user_id IS NULL
        '''),
        parameters: {'userId': userId},
      );

      final categories = result.map((row) {
        return {
          'id': row[0],
          'name': row[1],
          'icon': row[2],
          'color': row[3],
          'type': row[4],
          'status': row[5],
          'origin': row[6],
        };
      }).toList();

      return apiResponse(
        statusCode: HttpStatus.ok,
        message: 'Categories fetched successfully',
        data: categories,
      );
    } catch (e) {
      return apiResponse(
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to fetch categories',
      );
    }
  }

  if (method == HttpMethod.post) {
    try {
      final body = decodeObject(await context.request.body());
      final userId = context.read<String>();
      final pool = context.read<Pool<dynamic>>();
      if (body['name'] != null && body['name'] is! String ||
          body['type'] != null && body['type'] is! String ||
          body['icon'] != null && body['icon'] is! String ||
          body['color'] != null && body['color'] is! String) {
        throw const FormatException('Invalid category body');
      }

      final name = (body['name'] as String?)?.trim();
      final icon = (body['icon'] as String?)?.trim();
      final color = (body['color'] as String?)?.trim();
      final type = (body['type'] as String?)?.trim();

      if (name == null || name.isEmpty || name.length > 50) {
        return _error(
          HttpStatus.badRequest,
          'Name must contain 1-50 characters',
        );
      }
      if (type != 'expense' && type != 'income') {
        return _error(
          HttpStatus.badRequest,
          'Category type must be income or expense',
        );
      }
      if (color != null && !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
        return _error(HttpStatus.badRequest, 'Color must use #RRGGBB format');
      }

      final duplicate = await pool.execute(
        Sql.named('''
          SELECT id FROM categories
          WHERE lower(name) = lower(@name)
            AND type = @type
            AND (user_id = @userId OR user_id IS NULL)
          LIMIT 1
        '''),
        parameters: {'name': name, 'type': type, 'userId': userId},
      );
      if (duplicate.isNotEmpty) {
        return _error(HttpStatus.conflict, 'Category already exists');
      }

      final id = const Uuid().v4();
      await pool.execute(
        Sql.named('''
           INSERT INTO categories (id, user_id, name, icon, color, type, origin)
           VALUES (@id, @userId, @name, @icon, @color, @type, 'user_created')
        '''),
        parameters: {
          'id': id,
          'userId': userId,
          'name': name,
          'icon': icon == null || icon.isEmpty ? 'category' : icon,
          'color': color ?? '#78909C',
          'type': type,
        },
      );

      return apiResponse(
        statusCode: HttpStatus.created,
        message: 'Category created successfully',
        data: {
          'id': id,
          'name': name,
          'icon': icon == null || icon.isEmpty ? 'category' : icon,
          'color': color ?? '#78909C',
          'type': type,
        },
      );
    } on ServerException catch (error) {
      if (error.code == '23505') {
        return _error(HttpStatus.conflict, 'Category already exists');
      }
      return _error(
        HttpStatus.internalServerError,
        'Failed to create category',
      );
    } on FormatException {
      return _error(HttpStatus.badRequest, 'Invalid JSON body');
    } on TypeError {
      return _error(HttpStatus.badRequest, 'Invalid JSON body');
    } catch (_) {
      return _error(
        HttpStatus.internalServerError,
        'Failed to create category',
      );
    }
  }

  return _error(HttpStatus.methodNotAllowed, 'Method not allowed');
}

Response _error(int statusCode, String message) {
  return apiResponse(statusCode: statusCode, message: message);
}
