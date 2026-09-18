import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_test/dart_frog_test.dart';
import 'package:test/test.dart';

import '../../routes/api/v1/categories/index.dart' as categories;
import '../../routes/api/v1/categories/[id]/index.dart' as category_detail;
import '../../routes/api/v1/transactions/index.dart' as transactions;
import '../../routes/api/v1/transactions/[id].dart' as transaction_detail;

void main() {
  for (final payload in ['{', jsonEncode([]), jsonEncode('wrong')]) {
    test(
      'transaction create rejects malformed/non-object payload $payload',
      () async {
        final request = TestRequestContext(
          path: '/api/v1/transactions',
          method: HttpMethod.post,
          body: payload,
        );
        final response = await transactions.onRequest(request.context);
        expect(response.statusCode, HttpStatus.badRequest);
      },
    );

    test(
      'category create rejects malformed/non-object payload $payload',
      () async {
        final request = TestRequestContext(
          path: '/api/v1/categories',
          method: HttpMethod.post,
          body: payload,
        );
        final response = await categories.onRequest(request.context);
        expect(response.statusCode, HttpStatus.badRequest);
      },
    );

    test(
      'category update rejects malformed/non-object payload $payload',
      () async {
        final request = TestRequestContext(
          path: '/api/v1/categories/id',
          method: HttpMethod.patch,
          body: payload,
        );
        final response = await category_detail.onRequest(request.context, 'id');
        expect(response.statusCode, HttpStatus.badRequest);
      },
    );

    test(
      'transaction update rejects malformed/non-object payload $payload',
      () async {
        final request = TestRequestContext(
          path: '/api/v1/transactions/id',
          method: HttpMethod.put,
          body: payload,
        );
        final response = await transaction_detail.onRequest(
          request.context,
          'id',
        );
        expect(response.statusCode, HttpStatus.badRequest);
      },
    );
  }

  test(
    'transaction create rejects malformed category UUID before database access',
    () async {
      final request = TestRequestContext(
        path: '/api/v1/transactions',
        method: HttpMethod.post,
        body: jsonEncode({
          'category_id': 'bad',
          'amount': 1.00,
          'date': '2026-09-15T08:30:00.000Z',
        }),
      );
      expect(
        (await transactions.onRequest(request.context)).statusCode,
        HttpStatus.badRequest,
      );
    },
  );

  test('transaction create rejects three decimal amount', () async {
    final request = TestRequestContext(
      path: '/api/v1/transactions',
      method: HttpMethod.post,
      body: jsonEncode({
        'category_id': '00000000-0000-4000-8000-000000000001',
        'amount': 1.001,
        'date': '2026-09-15T08:30:00.000Z',
      }),
    );
    expect(
      (await transactions.onRequest(request.context)).statusCode,
      HttpStatus.badRequest,
    );
  });

  test('transaction create rejects scientific amount', () async {
    final request = TestRequestContext(
      path: '/api/v1/transactions',
      method: HttpMethod.post,
      body:
          '{"category_id":"00000000-0000-4000-8000-000000000001","amount":1e2,"date":"2026-09-15T08:30:00.000Z"}',
    );
    expect(
      (await transactions.onRequest(request.context)).statusCode,
      HttpStatus.badRequest,
    );
  });

  test('transaction update rejects three decimal amount', () async {
    final request = TestRequestContext(
      path: '/api/v1/transactions/00000000-0000-4000-8000-000000000001',
      method: HttpMethod.put,
      body: jsonEncode({
        'category_id': '00000000-0000-4000-8000-000000000001',
        'amount': 1.001,
        'date': '2026-09-15T08:30:00.000Z',
      }),
    );
    expect(
      (await transaction_detail.onRequest(
        request.context,
        '00000000-0000-4000-8000-000000000001',
      )).statusCode,
      HttpStatus.badRequest,
    );
  });

  test('transaction update rejects scientific amount', () async {
    final request = TestRequestContext(
      path: '/api/v1/transactions/00000000-0000-4000-8000-000000000001',
      method: HttpMethod.put,
      body:
          '{"category_id":"00000000-0000-4000-8000-000000000001","amount":1e2,"date":"2026-09-15T08:30:00.000Z"}',
    );
    expect(
      (await transaction_detail.onRequest(
        request.context,
        '00000000-0000-4000-8000-000000000001',
      )).statusCode,
      HttpStatus.badRequest,
    );
  });
}
