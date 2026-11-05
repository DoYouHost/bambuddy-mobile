import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// A write the server has answered is already committed (maziggy/bambuddy#3320,
/// fixed in 1.3.1 by `d8375fa`). Before it, `get_db` committed after the
/// response had gone out, so a read straight after a write could 404 or return
/// the old value.
///
/// A race of about 1 in 300 cannot be caught by running the suite, so this file
/// runs only against a server that commits a second late
/// (`tool/ci/delay_commit.sh`, the "Commit before response" step of
/// contract-tests.yml, which sets [_delayVariable]). There the answer to a
/// write is itself late on a fixed server, and the read after it must find the
/// row; on an unfixed one the answer comes at once and the read misses. Against
/// a normal server the file is skipped, because passing there would prove
/// nothing.
///
/// Built on a bare Dio, not [authenticatedDio]: its 100 ms hold on write
/// answers is the very thing that hides the race.
const _delayVariable = 'BAMBUDDY_CONTRACT_COMMIT_DELAY';

String? get _skipReason {
  if (contractSkipReason != null) return contractSkipReason;
  if ((Platform.environment[_delayVariable] ?? '').isEmpty) {
    return '$_delayVariable is unset: the server commits on time, so a pass '
        'would prove nothing';
  }
  return null;
}

void main() {
  group('commit before response contract', skip: _skipReason, () {
    late Dio dio;
    late bool unfixed;
    final made = <int>[];

    setUpAll(() async {
      unfixed = (await contractServerVersion()).baseBelow((1, 3, 1, 0));
      dio = createBareDio()..options.baseUrl = contractBaseUrl;
      final login = await rawLogin();
      dio.options.headers['Authorization'] = 'Bearer ${login['access_token']}';
    });

    tearDownAll(() async {
      if (unfixed) return;
      for (final id in made) {
        await dio.delete<dynamic>(
          Endpoints.project(id),
          options: Options(validateStatus: (_) => true),
        );
      }
    });

    bool known() {
      if (unfixed) markTestSkipped('server predates the 1.3.1 fix (#3320)');
      return unfixed;
    }

    /// A write that took a second proves the delay is in force and that the
    /// server waited for its commit; a quick one means either the delay is
    /// missing or the commit is still to come.
    Future<Response<T>> timed<T>(Future<Response<T>> write) async {
      final clock = Stopwatch()..start();
      final res = await write;
      expect(
        clock.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 800)),
        reason:
            'the write answered before the server could have committed it: '
            'either delay_commit.sh did not take effect, or this server '
            'responds first and commits after (#3320)',
      );
      return res;
    }

    Future<Response<Map<String, dynamic>>> read(int id) =>
        dio.get<Map<String, dynamic>>(
          Endpoints.project(id),
          options: Options(validateStatus: (_) => true),
        );

    test('a created row is there for the next read', () async {
      if (known()) return;
      final res = await timed(
        dio.post<Map<String, dynamic>>(
          Endpoints.projects,
          data: {
            'name': 'contract-commit-${DateTime.now().microsecondsSinceEpoch}',
          },
        ),
      );
      final id = res.data!['id'] as int;
      made.add(id);

      final got = await read(id);
      expect(got.statusCode, 200);
      expect(got.data!['name'], res.data!['name']);
    });

    test('an edited row reads its new value at once', () async {
      if (known()) return;
      final id =
          (await dio.post<Map<String, dynamic>>(
                Endpoints.projects,
                data: {'name': 'contract-before'},
              )).data!['id']
              as int;
      made.add(id);

      await timed(
        dio.patch<Map<String, dynamic>>(
          Endpoints.project(id),
          data: {'name': 'contract-after'},
        ),
      );

      final got = await read(id);
      expect(got.statusCode, 200);
      expect(got.data!['name'], 'contract-after');
    });

    test('a deleted row is gone for the next read', () async {
      if (known()) return;
      final id =
          (await dio.post<Map<String, dynamic>>(
                Endpoints.projects,
                data: {'name': 'contract-delete'},
              )).data!['id']
              as int;

      await timed(dio.delete<dynamic>(Endpoints.project(id)));

      expect((await read(id)).statusCode, 404);
    });
  });
}
