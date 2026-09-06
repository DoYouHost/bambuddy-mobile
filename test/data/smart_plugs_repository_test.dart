import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SmartPlugsRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = SmartPlugsRepository(dio);
  });

  test('fetchPlugs parsuje listę i mapuje printer_id', () async {
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

  test('fetchPlugs pomija niesparsowalny wpis, nie wywala listy', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/',
      (s) => s.reply(200, [
        {'id': 1, 'name': 'OK'},
        'śmieć',
        {'name': 'bez id'},
      ]),
    );
    final plugs = await repo.fetchPlugs();
    expect(plugs, hasLength(1));
    expect(plugs.single.id, 1);
  });

  test('fetchStatus wyciąga moc z energy.power', () async {
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

  test('fetchStatus: nieosiągalne gniazdko ma powerW == null', () async {
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
    expect(status.powerW, isNull); // moc nieaktualna gdy nieosiągalne
  });

  test('fetchStatus: błąd sieci/serwera degraduje się do null', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/9/status',
      (s) => s.reply(500, {'detail': 'boom'}),
    );
    expect(await repo.fetchStatus(9), isNull);
  });

  test('fetchStatus: 401 wypływa jako AuthException', () async {
    adapter.onGet(
      '/api/v1/smart-plugs/1/status',
      (s) => s.reply(401, {'detail': 'unauthorized'}),
    );
    await expectLater(repo.fetchStatus(1), throwsA(isA<AuthException>()));
  });

  test('control wysyła action w body JSON', () async {
    adapter.onPost(
      '/api/v1/smart-plugs/1/control',
      (s) => s.reply(200, null),
      data: {'action': 'off'},
    );
    await repo.control(1, SmartPlugAction.off); // brak wyjątku = OK
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
