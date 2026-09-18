import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../routes/api/v1/summary/overview.dart' as summary_route;
import '../../routes/api/v1/transactions/index.dart' as transactions;
import '../support/test_database.dart';

void main() {
  test('summary returns all fields for empty period', () async {
    final fixture = await _Fixture.create();
    try {
      final body = await fixture.summary();
      expect(body['status_code'], 200);
      expect(body['data'], {
        'total_income': 0,
        'total_expense': 0,
        'net_cash_flow_available': false,
        'net_cash_flow': null,
        'period': 'this_month',
        'summary': [],
        'largest_category': null,
      });
    } finally {
      await fixture.close();
    }
  }, skip: _skipDbTest);

  test(
    'summary supports expense-only, income-only, and full periods',
    () async {
      final fixture = await _Fixture.create();
      try {
        await fixture.insertTransaction(amount: 10.25, type: 'expense');
        var data = (await fixture.summary())['data'] as Map<String, dynamic>;
        expect(data['total_income'], 0);
        expect(data['total_expense'], 10.25);
        expect(data['net_cash_flow_available'], false);
        expect(data['net_cash_flow'], null);
        expect(data['summary'], hasLength(1));
        expect(data['largest_category'], isNotNull);

        await fixture.clearTransactions();
        await fixture.insertTransaction(amount: 100.10, type: 'income');
        data = (await fixture.summary())['data'] as Map<String, dynamic>;
        expect(data['total_income'], 100.10);
        expect(data['total_expense'], 0);
        expect(data['net_cash_flow_available'], true);
        expect(data['net_cash_flow'], 100.10);
        expect(data['summary'], isEmpty);
        expect(data['largest_category'], null);

        await fixture.insertTransaction(amount: 0.10, type: 'expense');
        data = (await fixture.summary())['data'] as Map<String, dynamic>;
        expect(data['total_income'], 100.10);
        expect(data['total_expense'], 0.10);
        expect(data['net_cash_flow_available'], true);
        expect(data['net_cash_flow'], 100.0);
      } finally {
        await fixture.close();
      }
    },
    skip: _skipDbTest,
  );

  test(
    'summary uses UTC boundaries and normalizes timezone-offset dates',
    () async {
      final fixture = await _Fixture.create();
      try {
        final now = DateTime.now().toUtc();
        final start = DateTime.utc(now.year, now.month);
        final previousStart = DateTime.utc(now.year, now.month - 1);
        final previousEnd = start;
        await fixture.insertTransaction(
          amount: 1,
          type: 'income',
          // Local +07 input normalizes exactly to current UTC period start.
          date:
              '${start.add(const Duration(hours: 7)).toIso8601String().replaceFirst('Z', '+07:00')}',
        );
        await fixture.insertTransaction(
          amount: 2,
          type: 'income',
          // Local -05 input normalizes exactly to current UTC period start.
          date:
              '${previousEnd.subtract(const Duration(hours: 5)).toIso8601String().replaceFirst('Z', '-05:00')}',
        );
        await fixture.insertTransaction(
          amount: 4,
          type: 'income',
          // Previous UTC period start stays out of current period.
          date: previousStart.toIso8601String(),
        );
        var data = (await fixture.summary())['data'] as Map<String, dynamic>;
        expect(data['total_income'], 3);

        data =
            (await fixture.summary(period: 'previous_month'))['data']
                as Map<String, dynamic>;
        expect(data['total_income'], 4);
      } finally {
        await fixture.close();
      }
    },
    skip: _skipDbTest,
  );

  test('legacy omitted transaction type stores expense', () async {
    final fixture = await _Fixture.create();
    try {
      final request = TestRequestContext(
        path: '/api/v1/transactions',
        method: HttpMethod.post,
        body: jsonEncode({
          'category_id': fixture.categoryId,
          'amount': 12.34,
          'date': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      request.provide<String>(fixture.userId);
      request.provide<Pool<dynamic>>(fixture.pool);
      expect(
        (await transactions.onRequest(request.context)).statusCode,
        HttpStatus.created,
      );
      final rows = await fixture.pool.execute(
        Sql.named('SELECT type, amount FROM transactions WHERE user_id = @id'),
        parameters: {'id': fixture.userId},
      );
      expect(rows.single[0], 'expense');
      expect(num.parse(rows.single[1].toString()), 12.34);
    } finally {
      await fixture.close();
    }
  }, skip: _skipDbTest);
}

class _Fixture {
  _Fixture(this.pool, this.userId, this.categoryId, this.incomeCategoryId);

  final Pool<dynamic> pool;
  final String userId;
  final String categoryId;
  final String incomeCategoryId;

  static Future<_Fixture> create() async {
    final pool = _pool();
    final userId = const Uuid().v4();
    final categoryId = const Uuid().v4();
    final incomeCategoryId = const Uuid().v4();
    await pool.execute(
      Sql.named(
        'INSERT INTO users (id, email, password_hash) VALUES (@id, @email, \'test\')',
      ),
      parameters: {'id': userId, 'email': '$userId@example.com'},
    );
    await pool.execute(
      Sql.named(
        '''INSERT INTO categories
        (id, user_id, name, type, status, origin)
        VALUES (@id, @user, 'Test expense', 'expense', 'active', 'user_created')''',
      ),
      parameters: {'id': categoryId, 'user': userId},
    );
    await pool.execute(
      Sql.named(
        '''INSERT INTO categories
        (id, user_id, name, type, status, origin)
        VALUES (@id, @user, 'Test income', 'income', 'active', 'user_created')''',
      ),
      parameters: {'id': incomeCategoryId, 'user': userId},
    );
    return _Fixture(pool, userId, categoryId, incomeCategoryId);
  }

  Future<void> insertTransaction({
    required num amount,
    required String type,
    String? date,
  }) => pool.execute(
    Sql.named(
      '''INSERT INTO transactions
          (id, user_id, type, category_id, amount, date)
          VALUES (@id, @user, @type, @category, @amount, COALESCE(@date, CURRENT_TIMESTAMP))''',
    ),
    parameters: {
      'id': const Uuid().v4(),
      'user': userId,
      'type': type,
      'category': type == 'income' ? incomeCategoryId : categoryId,
      'amount': amount,
      'date': date == null ? null : DateTime.parse(date),
    },
  );

  Future<void> clearTransactions() => pool.execute(
    Sql.named('DELETE FROM transactions WHERE user_id = @id'),
    parameters: {'id': userId},
  );

  Future<Map<String, dynamic>> summary({String period = 'this_month'}) async {
    final request = TestRequestContext(
      path: '/api/v1/summary/overview?period=$period',
      method: HttpMethod.get,
    );
    request.provide<String>(userId);
    request.provide<Pool<dynamic>>(pool);
    return (await (await summaryOn(request)).json()) as Map<String, dynamic>;
  }

  Future<Response> summaryOn(TestRequestContext request) async =>
      await summary_route.onRequest(request.context);

  Future<void> close() async {
    await pool.execute(
      Sql.named('DELETE FROM users WHERE id = @id'),
      parameters: {'id': userId},
    );
    await pool.close();
  }
}

Pool<dynamic> _pool() =>
    testPool();

bool get _skipDbTest =>
    Platform.environment['DATABASE_URL'] == null ||
    (Platform.environment['JWT_SECRET']?.length ?? 0) < 32;
