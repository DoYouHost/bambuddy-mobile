import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// "Server timestamps are UTC even when the `Z` is missing" is a rule the whole
/// app is built on — every model routes its dates through [dateTimeFromJson]
/// instead of `DateTime.parse` because of it.
///
/// `test/core/models/json_utils_test.dart` proves the parser honours that rule.
/// Nothing proved the rule itself: the fixtures asserting it were written from
/// the same belief as the parser, so if bambuddy ever answered in local time
/// the suite would stay green and every duration in the app would be wrong by
/// the device's offset.
///
/// This file only bites when the test process runs OUTSIDE UTC — on a UTC host,
/// reading a naive timestamp as local and reading it as UTC land on the same
/// instant, so both a correct and a broken parser pass. The workflow therefore
/// sets TZ on the step; measured, not assumed, by swapping dateTimeFromJson for
/// a naive DateTime.parse and watching it pass under TZ=UTC and fail by two
/// hours under TZ=Europe/Warsaw. Do not drop that TZ thinking it is cosmetic.
///
/// The server's own zone is not the variable here: it writes UTC whether its
/// container has TZ set or not, which was checked both ways.
void main() {
  group('timestamp contract', skip: contractSkipReason, () {
    late Dio dio;

    setUpAll(() async {
      dio = await authenticatedDio();
    });

    test('a fresh record is stamped in UTC, with no zone suffix', () async {
      // Measured with a bracket rather than against a single "now": the record
      // is created between two readings of the clock, so the assertion holds on
      // a runner in any zone. Comparing in UTC on both sides is what makes it
      // zone-independent — a server that switched to local time would land
      // outside the bracket by its whole offset.
      final before = DateTime.now().toUtc();
      final created = await dio.post<Map<String, dynamic>>(
        Endpoints.maintenanceTypes,
        data: {
          'name': 'ZZ contract probe',
          'description': 'created and deleted by the contract suite',
          'default_interval_hours': 100,
        },
      );
      final after = DateTime.now().toUtc();

      final body = created.data;
      expect(body, isNotNull);
      final id = body!['id'];

      try {
        final raw = body['created_at'];
        expect(raw, isA<String>(), reason: 'no created_at to check');

        // The half a fixture cannot assert: what the server actually writes.
        expect(
          RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw as String),
          isFalse,
          reason:
              'created_at now carries a zone suffix ($raw). That is an improvement, '
              'not a break — but dateTimeFromJson only appends Z when one is '
              'absent, so confirm the suffix is honoured before relaxing this',
        );

        final parsed = dateTimeFromJson(raw)!.toUtc();
        final low = before.subtract(const Duration(seconds: 5));
        final high = after.add(const Duration(seconds: 5));

        expect(
          parsed.isAfter(low) && parsed.isBefore(high),
          isTrue,
          reason:
              'created_at $raw parsed to $parsed, outside the $low..$high window '
              'the request was made in. A whole-hour miss means the server is '
              'writing local time, and every elapsed-time reading in the app is '
              'off by that much',
        );
      } finally {
        // The CI server is thrown away with the job, but leaving the probe
        // behind would make the maintenance screens lie in any other setup.
        await dio.delete<dynamic>(
          '${Endpoints.maintenanceTypes}/$id',
          options: Options(validateStatus: (_) => true),
        );
      }
    });
  });
}
