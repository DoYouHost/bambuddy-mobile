import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PrinterCommandsRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = PrinterCommandsRepository(dio);
  });

  test('pause/resume/stop trafiają w poprawne ścieżki POST', () async {
    adapter
      ..onPost('/api/v1/printers/1/print/pause', (s) => s.reply(200, null))
      ..onPost('/api/v1/printers/1/print/resume', (s) => s.reply(200, null))
      ..onPost('/api/v1/printers/1/print/stop', (s) => s.reply(200, null));

    // Brak wyjątku = sukces.
    await repo.pause(1);
    await repo.resume(1);
    await repo.stop(1);
  });

  test('chamber-light wysyła on=true w query', () async {
    adapter.onPost(
      '/api/v1/printers/2/chamber-light',
      (s) => s.reply(200, null),
      queryParameters: {'on': true},
    );
    await repo.setChamberLight(2, on: true);
  });

  test('print-speed wysyła mode w query', () async {
    adapter.onPost(
      '/api/v1/printers/3/print-speed',
      (s) => s.reply(200, null),
      queryParameters: {'mode': 3},
    );
    await repo.setPrintSpeed(3, 3);
  });

  test('403 → AuthException(forbidden) — brak can_control_printer', () async {
    adapter.onPost(
      '/api/v1/printers/1/print/pause',
      (s) => s.reply(403, {'detail': 'forbidden'}),
    );
    await expectLater(
      repo.pause(1),
      throwsA(
        isA<AuthException>().having((e) => e.code, 'code',
            AppErrorCode.forbidden),
      ),
    );
  });

  test('401 → AuthException(unauthorized), nie mylone z 403', () async {
    adapter.onPost(
      '/api/v1/printers/1/print/stop',
      (s) => s.reply(401, {'detail': 'unauthorized'}),
    );
    await expectLater(
      repo.stop(1),
      throwsA(
        isA<AuthException>().having((e) => e.code, 'code',
            AppErrorCode.unauthorized),
      ),
    );
  });

  test('5xx → ApiException(badResponse)', () async {
    adapter.onPost(
      '/api/v1/printers/1/print/resume',
      (s) => s.reply(500, {'detail': 'boom'}),
    );
    await expectLater(repo.resume(1), throwsA(isA<ApiException>()));
  });
}
