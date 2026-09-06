import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;

  const slim = '/api/v1/users/slim';
  const full = '/api/v1/users/';

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        noServerProfileOverride,
        statsRepositoryProvider.overrideWithValue(StatsRepository(dio)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('a refusal means "not for you" — empty list, picker hidden', () async {
    // 403 on slim is how a pre-1.2.6 server declines the route, so the
    // repository still falls back before the refusal is final.
    adapter
      ..onGet(slim, (s) => s.reply(403, {'detail': 'Forbidden'}))
      ..onGet(full, (s) => s.reply(403, {'detail': 'Forbidden'}));

    expect(await container().read(statsUsersProvider.future), isEmpty);
  });

  test('an unreachable server is not a refusal — the error surfaces', () async {
    // Absorbed, this read as "you have no permission" and hid the picker for a
    // server that was simply down.
    adapter.onGet(slim, (s) => s.reply(500, {'detail': 'boom'}));

    await expectLater(
      container().read(statsUsersProvider.future),
      throwsA(isA<AppApiException>()),
    );
  });

  test('a working listing comes through sorted', () async {
    adapter.onGet(
      slim,
      (s) => s.reply(200, [
        {'id': 2, 'username': 'zosia'},
        {'id': 1, 'username': 'admin'},
      ]),
    );

    final users = await container().read(statsUsersProvider.future);

    expect(users.map((u) => u.username), ['admin', 'zosia']);
  });
}
