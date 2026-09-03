import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:clock/clock.dart';
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

  /// Counts the requests that really left the app and answers them here.
  /// A counter inside `adapter.onGet(...)` counts route REGISTRATIONS — the
  /// handler is invoked once, when the route is declared — so it reads `1`
  /// whether the service asked once, twice or never.
  int Function() countingReplies(Response<dynamic> Function() reply) {
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      final staged = reply();
      handler.resolve(Response(
        requestOptions: options,
        statusCode: staged.statusCode,
        data: staged.data,
      ));
    }));
    return () => requests;
  }

  void replyVersion(String version) => adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(200, {'version': version, 'repo': 'x/y'}),
      );

  test('czyta wersję i rozpoznaje trójstan', () async {
    replyVersion('1.2.5.1');

    expect((await service.current())?.raw, '1.2.5.1');
    expect(await service.supports(ServerFeature.triStateCalibration), isTrue);
    expect(await service.reportedVersion(), '1.2.5.1');
  });

  test('starszy serwer: trójstanu nie ma', () async {
    replyVersion('0.2.4.9');

    expect(await service.supports(ServerFeature.triStateCalibration), isFalse);
  });

  test('pyta raz, potem korzysta z zapamiętanej odpowiedzi', () async {
    final calls = countingReplies(() => Response(
          requestOptions: RequestOptions(),
          statusCode: 200,
          data: {'version': '1.2.5', 'repo': 'x/y'},
        ));

    await service.current();
    await service.current();
    await service.supports(ServerFeature.triStateCalibration);

    expect(calls(), 1, reason: 'wersja nie zmienia się bez restartu serwera');
  });

  test('równoległe wywołania dzielą jedno żądanie', () async {
    final calls = countingReplies(() => Response(
          requestOptions: RequestOptions(),
          statusCode: 200,
          data: {'version': '1.2.5', 'repo': 'x/y'},
        ));

    await Future.wait([
      service.current(),
      service.current(),
      service.current(),
    ]);

    expect(calls(), 1);
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
      expect(await service.supports(ServerFeature.triStateCalibration), isFalse,
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
      final calls = countingReplies(
          () => Response(requestOptions: RequestOptions(), statusCode: 500));

      await service.current();
      await service.current();

      expect(calls(), 1, reason: 'w oknie ponowienia nie dobija serwera');
      expect(service.cached, isNull);
    });

    test('past the retry window the read is attempted again', () async {
      // The other half of the rule above, and the half that decides whether a
      // feature comes back at all: a probe that met a moment without a network
      // has to be retried once the window is out, not once the app restarts.
      final calls = countingReplies(
          () => Response(requestOptions: RequestOptions(), statusCode: 500));

      final failedAt = DateTime(2026, 9, 3, 12);
      await withClock(Clock.fixed(failedAt), () async {
        await service.current();
        await service.current();
      });
      expect(calls(), 1, reason: 'inside the window the server is left alone');

      await withClock(Clock.fixed(failedAt.add(const Duration(minutes: 6))),
          () async {
        await service.current();
      });
      expect(calls(), 2);
    });
  });
}
