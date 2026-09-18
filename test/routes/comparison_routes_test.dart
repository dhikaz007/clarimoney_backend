import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../routes/api/v1/categories/[id]/comparison.dart' as category_route;
import '../../routes/api/v1/summary/comparison/index.dart' as overview_route;
import '../../routes/api/v1/summary/comparison/categories.dart'
    as categories_route;

void main() {
  test(
    'comparison routes return full ranges and persistent category identity',
    () async {
      final fixture = await _Fixture.create();
      try {
        final now = DateTime.now().toUtc();
        final currentDate = DateTime.utc(now.year, now.month, 5);
        final previousDate = DateTime.utc(now.year, now.month - 1, 5);
        await fixture.insertTransaction(
          amount: 10,
          type: 'expense',
          date: currentDate,
        );
        await fixture.insertTransaction(
          amount: 4,
          type: 'expense',
          date: previousDate,
        );

        final overview = await fixture.call(overview_route.onRequest);
        expect(overview['status_code'], HttpStatus.ok);
        final data = overview['data'] as Map<String, dynamic>;
        final monthStart = DateTime.utc(now.year, now.month);
        final monthEnd = DateTime.utc(now.year, now.month + 1);
        final previousStart = DateTime.utc(now.year, now.month - 1);
        expect(data['periods'], {
          'current': {'start': _iso(monthStart), 'end': _iso(monthEnd)},
          'previous': {'start': _iso(previousStart), 'end': _iso(monthStart)},
        });
        expect(data['expense']['absolute_change'], 6);
        expect(data['drivers'], isA<List<dynamic>>());

        final categories = await fixture.call(categories_route.onRequest);
        expect(
          (categories['data'] as Map<String, dynamic>)['categories'],
          containsPair(
            fixture.categoryId,
            containsPair('category_id', fixture.categoryId),
          ),
        );

        final detail = await fixture.call(
          (request) => category_route.onRequest(request, fixture.categoryId),
        );
        expect(detail['status_code'], HttpStatus.ok);
        expect(
          (detail['data'] as Map<String, dynamic>)['category_id'],
          fixture.categoryId,
        );
      } finally {
        await fixture.close();
      }
    },
    skip: _skipDbTest,
  );

  test(
    'category comparison rejects category owned by another user',
    () async {
      final fixture = await _Fixture.create();
      final other = await _Fixture.create();
      try {
        final request = TestRequestContext(
          path:
              '/api/v1/categories/${other.categoryId}/comparison?period=this_month',
          method: HttpMethod.get,
        );
        request.provide<String>(fixture.userId);
        request.provide<Pool<dynamic>>(fixture.pool);
        final response = await category_route.onRequest(
          request.context,
          other.categoryId,
        );
        expect(response.statusCode, HttpStatus.notFound);
      } finally {
        await other.close();
        await fixture.close();
      }
    },
    skip: _skipDbTest,
  );
}

class _Fixture {
  _Fixture(this.pool, this.userId, this.categoryId);
  final Pool<dynamic> pool;
  final String userId;
  final String categoryId;

  static Future<_Fixture> create() async {
    final pool = Pool<dynamic>.withUrl(Platform.environment['DATABASE_URL']!);
    final userId = const Uuid().v4();
    final categoryId = const Uuid().v4();
    await pool.execute(
      Sql.named(
        "INSERT INTO users (id, email, password_hash) VALUES (@id, @email, 'test')",
      ),
      parameters: {'id': userId, 'email': '$userId@example.com'},
    );
    await pool.execute(
      Sql.named('''
      INSERT INTO categories (id, user_id, name, type, status, origin)
      VALUES (@id, @user, 'Test expense', 'expense', 'active', 'user_created')
    '''),
      parameters: {'id': categoryId, 'user': userId},
    );
    return _Fixture(pool, userId, categoryId);
  }

  Future<void> insertTransaction({
    required num amount,
    required String type,
    required DateTime date,
  }) => pool.execute(
    Sql.named('''
        INSERT INTO transactions (id, user_id, type, category_id, amount, date)
        VALUES (@id, @user, @type, @category, @amount, @date)
      '''),
    parameters: {
      'id': const Uuid().v4(),
      'user': userId,
      'type': type,
      'category': categoryId,
      'amount': amount,
      'date': date,
    },
  );

  Future<Map<String, dynamic>> call(
    FutureOr<Response> Function(RequestContext) handler,
  ) async {
    final request = TestRequestContext(
      path: '/api/v1/summary/comparison?period=this_month',
      method: HttpMethod.get,
    );
    request.provide<String>(userId);
    request.provide<Pool<dynamic>>(pool);
    return (await (await handler(request.context)).json())
        as Map<String, dynamic>;
  }

  Future<void> close() async {
    await pool.execute(
      Sql.named('DELETE FROM users WHERE id = @id'),
      parameters: {'id': userId},
    );
    await pool.close();
  }
}

bool get _skipDbTest =>
    Platform.environment['DATABASE_URL'] == null ||
    (Platform.environment['JWT_SECRET']?.length ?? 0) < 32;

String _iso(DateTime value) =>
    '${value.toUtc().toIso8601String().split('.').first}.000Z';
