import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/discovery_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late DiscoveryRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = DiscoveryRepository(dio);
  });

  group('DiscoveryRepository', () {
    test('info decodes environment info and candidate subnets', () async {
      adapter.onGet(
        Endpoints.discoveryInfo,
        (s) => s.reply(200, {
          'is_docker': true,
          'subnets': ['192.168.1.0/24', '10.0.0.0/24'],
        }),
      );

      final info = await repo.info();
      expect(info.isDocker, isTrue);
      expect(info.subnets, ['192.168.1.0/24', '10.0.0.0/24']);
    });

    test('startScan initiates subnet scan and parses initial status', () async {
      adapter.onPost(
        Endpoints.discoveryScan,
        (s) => s.reply(200, {
          'running': true,
          'scanned': 0,
          'total': 254,
        }),
        data: {'subnet': '192.168.1.0/24', 'timeout': 1.5},
      );

      final status = await repo.startScan('192.168.1.0/24', timeout: 1.5);
      expect(status.running, isTrue);
      expect(status.scanned, 0);
      expect(status.total, 254);
    });

    test('scanStatus parses polling response', () async {
      adapter.onGet(
        Endpoints.discoveryScanStatus,
        (s) => s.reply(200, {
          'running': false,
          'scanned': 254,
          'total': 254,
        }),
      );

      final status = await repo.scanStatus();
      expect(status.running, isFalse);
      expect(status.scanned, 254);
      expect(status.total, 254);
    });

    test('startSsdp sends duration parameter', () async {
      adapter.onPost(
        Endpoints.discoveryStart,
        (s) => s.reply(200, {'started': true}),
        queryParameters: {'duration': 15.0},
      );

      await expectLater(repo.startSsdp(duration: 15.0), completes);
    });

    test('stopSsdp sends post request', () async {
      adapter.onPost(
        Endpoints.discoveryStop,
        (s) => s.reply(200, {'stopped': true}),
      );

      await expectLater(repo.stopSsdp(), completes);
    });

    test('discoveredPrinters parses list of found printers', () async {
      adapter.onGet(
        Endpoints.discoveryPrinters,
        (s) => s.reply(200, [
          {
            'serial': '00M09A123456789',
            'name': 'Living Room X1C',
            'ip_address': '192.168.1.105',
            'model': 'X1C',
          },
          {
            'serial': '01P00A987654321',
            'name': 'Office P1S',
            'ip_address': '192.168.1.106',
            'model': '',
          },
        ]),
      );

      final printers = await repo.discoveredPrinters();
      expect(printers, hasLength(2));

      expect(printers[0].serial, '00M09A123456789');
      expect(printers[0].name, 'Living Room X1C');
      expect(printers[0].ipAddress, '192.168.1.105');
      expect(printers[0].model, 'X1C');

      expect(printers[1].serial, '01P00A987654321');
      expect(printers[1].name, 'Office P1S');
      expect(printers[1].ipAddress, '192.168.1.106');
      expect(printers[1].model, isNull);
    });

    test('discoveredPrinters gracefully ignores non-map elements', () async {
      adapter.onGet(
        Endpoints.discoveryPrinters,
        (s) => s.reply(200, [
          'invalid_string',
          42,
          {
            'serial': '00M09A123456789',
            'name': 'Living Room X1C',
            'ip_address': '192.168.1.105',
          },
        ]),
      );

      final printers = await repo.discoveredPrinters();
      expect(printers, hasLength(1));
      expect(printers.single.serial, '00M09A123456789');
    });

    test('handles 403 forbidden with AuthException via guard', () async {
      adapter.onGet(
        Endpoints.discoveryInfo,
        (s) => s.reply(403, {'detail': 'Permission DISCOVERY_SCAN required'}),
      );

      expect(
        () => repo.info(),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
