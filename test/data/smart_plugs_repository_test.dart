import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SmartPlugsRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = SmartPlugsRepository(dio);
  });

  test('fetchPlugs parses the list and maps printer_id', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/',
      (s) => s.reply(200, [
        {
          'id': 1,
          'name': 'Szafa',
          'plug_type': 'homeassistant',
          'printer_id': 7,
          'enabled': true,
          'last_state': 'OFF',
          'show_on_printer_card': true,
        },
      ]),
    );

    final plugs = await repo.fetchPlugs();
    expect(plugs, hasLength(1));
    expect(plugs.single.printerId, 7);
    expect(plugs.single.visibleOnCard, isTrue);
    expect(plugs.single.lastIsOn, isFalse);
  });

  test(
    'fetchPlugs skips an unparseable entry, does not crash the list',
    () async {
      adapter.onGet(
        '/api/v1/smart-plugs/',
        (s) => s.reply(200, [
          {'id': 1, 'name': 'OK'},
          'junk',
          {'name': 'no id'},
        ]),
      );
      final plugs = await repo.fetchPlugs();
      expect(plugs, hasLength(1));
      expect(plugs.single.id, 1);
    },
  );

  test('fetchStatus extracts power from energy.power', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/1/status',
      (s) => s.reply(200, {
        'state': 'ON',
        'reachable': true,
        'device_name': 'Szafa',
        'energy': {'power': 42.5, 'total': 129.66},
      }),
    );
    final status = await repo.fetchStatus(1);
    expect(status, isNotNull);
    expect(status!.isOn, isTrue);
    expect(status.powerW, 42.5);
    expect(status.energy?.total, 129.66);
  });

  test('fetchStatus: an unreachable plug has powerW == null', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/1/status',
      (s) => s.reply(200, {
        'state': null,
        'reachable': false,
        'energy': {'power': 10.0},
      }),
    );
    final status = await repo.fetchStatus(1);
    expect(status!.isReachable, isFalse);
    expect(status.powerW, isNull); // power is stale when unreachable
  });

  test('fetchStatus: network/server error degrades to null', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/9/status',
      (s) => s.reply(500, {'detail': 'boom'}),
    );
    expect(await repo.fetchStatus(9), isNull);
  });

  test('fetchStatus: 401 flows out as AuthException', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/1/status',
      (s) => s.reply(401, {'detail': 'unauthorized'}),
    );
    await expectLater(repo.fetchStatus(1), throwsA(isA<AuthException>()));
  });

  test('control sends action in the JSON body', () async {
    adapter.onPost(
      '/api/v1/smart-plugs/1/control',
      (s) => s.reply(200, null),
      data: {'action': 'off'},
    );
    await repo.control(1, SmartPlugAction.off); // no exception = OK
  });

  test('control: 403 → AuthException(forbidden)', () async {
    adapter.onPost(
      '/api/v1/smart-plugs/1/control',
      (s) => s.reply(403, {'detail': 'forbidden'}),
      data: {'action': 'on'},
    );
    await expectLater(
      repo.control(1, SmartPlugAction.on),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.forbidden,
        ),
      ),
    );
  });
}
