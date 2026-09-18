import 'dart:async';
import 'dart:io';
import 'package:clarimoney_backend/src/api_response.dart';
import 'package:clarimoney_backend/src/comparison_route.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

FutureOr<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return apiResponse(
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed',
    );
  }
  final period = context.request.uri.queryParameters['period'] ?? 'this_month';
  if (period != 'this_month' && period != 'previous_month') {
    return apiResponse(
      statusCode: HttpStatus.badRequest,
      message: 'period must be this_month or previous_month',
    );
  }
  try {
    final data = await fetchComparison(
      pool: context.read<Pool<dynamic>>(),
      userId: context.read<String>(),
      period: period,
      includeEmptyCategories: true,
    );
    final categories = (data['categories'] as Map<String, dynamic>).values
        .map((value) => value as Map<String, dynamic>)
        .map(
          (value) => {
            'category_id': value['category_id'],
            'name': value['name'],
            'current': value['current'],
            'previous': value['previous'],
            'absolute_change': value['absolute_change'],
            'percentage_change': value['percentage_change'],
          },
        )
        .toList();
    return apiResponse(
      statusCode: HttpStatus.ok,
      message: 'Category comparison fetched successfully',
      data: {
        'period': data['period'],
        'periods': data['periods'],
        'categories': categories,
        'drivers': data['drivers'],
      },
    );
  } catch (_) {
    return apiResponse(
      statusCode: HttpStatus.internalServerError,
      message: 'Failed to fetch category comparison',
    );
  }
}
