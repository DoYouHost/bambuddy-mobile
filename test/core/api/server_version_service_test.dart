import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ServerVersionService service;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    service = ServerVersionService(dio);
  });

  void replyVersion(String version) => adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(200, {'version': version, 'repo': 'x/y'}),
      );

  test('czyta wersję i rozpoznaje trójstan', () async {
    replyVersion('1.2.5.1');

    expect((await service.current())?.raw, '1.2.5.1');
    expect(await service.supportsTriStateCalibration(), isTrue);
    expect(await service.reportedVersion(), '1.2.5.1');
  });

  test('starszy serwer: trójstanu nie ma', () async {
    replyVersion('0.2.4.9');

    expect(await service.supportsTriStateCalibration(), isFalse);
  });

  test('pyta raz, potem korzysta z zapamiętanej odpowiedzi', () async {
    var calls = 0;
    adapter.onGet('/api/v1/updates/version', (server) {
      calls++;
      return server.reply(200, {'version': '1.2.5', 'repo': 'x/y'});
    });

    await service.current();
    await service.current();
    await service.supportsTriStateCalibration();

    expect(calls, 1, reason: 'wersja nie zmienia się bez restartu serwera');
  });

  test('równoległe wywołania dzielą jedno żądanie', () async {
    var calls = 0;
    adapter.onGet('/api/v1/updates/version', (server) {
      calls++;
      return server.reply(200, {'version': '1.2.5', 'repo': 'x/y'});
    });

    await Future.wait([
      service.current(),
      service.current(),
      service.current(),
    ]);

    expect(calls, 1);
  });

  test('cached: bez sieci nie zgaduje', () async {
    replyVersion('1.2.5');
    expect(service.cached, isNull, reason: 'przed odczytem nic nie wiadomo');

    await service.current();

    expect(service.cached?.raw, '1.2.5');
  });

  group('serwer nie odpowiada tym, czego oczekujemy', () {
    test('błąd HTTP → brak wersji, bez wyjątku', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(500, null),
      );

      expect(await service.current(), isNull);
      expect(await service.supportsTriStateCalibration(), isFalse,
          reason: 'nieznane traktujemy jak starsze');
      expect(await service.reportedVersion(), isNull);
    });

    test('404 (route przeniesiony) też jest odpowiedzią, nie awarią', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(404, null),
      );

      expect(await service.current(), isNull);
    });

    test('nie-wersja w polu version → brak wersji', () async {
      replyVersion('nie-wersja');

      expect(await service.current(), isNull);
    });

    test('body bez pola version', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(200, {'repo': 'x/y'}),
      );

      expect(await service.current(), isNull);
    });

    test('nieudany odczyt nie jest zapamiętywany na stałe', () async {
      // Sonda, która trafiła w moment bez sieci, nie może wyłączyć auto na całą
      // sesję — inaczej jedna chwila offline kosztuje funkcję do restartu apki.
      var calls = 0;
      adapter.onGet('/api/v1/updates/version', (server) {
        calls++;
        return server.reply(500, null);
      });

      await service.current();
      await service.current();

      expect(calls, 1, reason: 'w oknie ponowienia nie dobija serwera');
      expect(service.cached, isNull);
    });
  });
}
