import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/location_sensor.dart';
import 'package:bambuddy_mobile/data/location_sensors_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late LocationSensorsRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = LocationSensorsRepository(dio, ServerVersionService(dio));
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  group('listBindings', () {
    test(
      'reads the location each sensor hangs off, and whether it shows',
      () async {
        adapter.onGet(
          '/api/v1/location-ha-sensors/',
          (s) => s.reply(200, [
            {
              'id': 4,
              'location_id': 3,
              'name': 'Humidity',
              'entity_id': 'sensor.dry_box_humidity',
              'kind': 'numeric',
              'show_on_card': true,
              'created_at': '2026-08-30T10:00:00Z',
              'updated_at': '2026-08-30T10:00:00Z',
            },
            {
              'id': 5,
              'location_id': 3,
              'name': 'Door',
              'entity_id': 'binary_sensor.dry_box_door',
              'kind': 'binary',
              'show_on_card': false,
              'created_at': '2026-08-30T10:00:00Z',
              'updated_at': '2026-08-30T10:00:00Z',
            },
          ]),
        );

        final rows = await repo.listBindings();

        expect(rows.map((r) => r.id), [4, 5]);
        expect(rows.map((r) => r.locationId), [3, 3]);
        expect(rows.map((r) => r.showOnCard), [true, false]);
      },
    );

    test(
      'a 404 answers with nothing rather than throwing at a screen',
      () async {
        adapter.onGet(
          '/api/v1/location-ha-sensors/',
          (s) => s.reply(404, {'detail': 'Not Found'}),
        );

        expect(await repo.listBindings(), isEmpty);
      },
    );

    test('a 403 answers the same way — an API key cannot read these', () async {
      adapter.onGet(
        '/api/v1/location-ha-sensors/',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );

      expect(await repo.listBindings(), isEmpty);
    });

    test('any other failure is still a failure', () async {
      adapter.onGet(
        '/api/v1/location-ha-sensors/',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(repo.listBindings(), throwsA(isA<AppApiException>()));
    });
  });

  group('readings', () {
    test('parses a numeric reading, its unit and its alert state', () async {
      adapter.onGet(
        '/api/v1/location-ha-sensors/by-location/3/readings',
        (s) => s.reply(200, [
          {
            'id': 4,
            'name': 'Humidity',
            'entity_id': 'sensor.dry_box_humidity',
            'kind': 'numeric',
            'device_class': 'humidity',
            'unit': '%',
            'state': '47.2',
            'value': 47.2,
            'alerting': true,
            'reachable': true,
            'alert_above': 45.0,
            'last_changed': '2026-09-04T08:15:00Z',
            'show_on_card': true,
          },
        ]),
      );

      final reading = (await repo.readings(3)).single;

      expect(reading.name, 'Humidity');
      expect(reading.numeric, isTrue);
      expect(reading.category, LocationSensorCategory.humidity);
      expect(reading.formattedValue, '47.2%');
      expect(reading.alerting, isTrue);
      expect(reading.reachable, isTrue);
      // Local for display, but the same instant the server named.
      expect(reading.lastChanged!.isUtc, isFalse);
      expect(reading.lastChanged!.toUtc(), DateTime.utc(2026, 9, 4, 8, 15));
    });

    test(
      'a stamp without the Z is UTC too, not the phone\'s wall clock',
      () async {
        adapter.onGet(
          '/api/v1/location-ha-sensors/by-location/3/readings',
          (s) => s.reply(200, [
            {
              'id': 4,
              'name': 'Humidity',
              'kind': 'numeric',
              'last_changed': '2026-09-04T08:15:00',
            },
          ]),
        );

        final reading = (await repo.readings(3)).single;

        expect(reading.lastChanged!.toUtc(), DateTime.utc(2026, 9, 4, 8, 15));
      },
    );

    test(
      'a sensor the poller has not reached yet is not passed off as fresh',
      () async {
        adapter.onGet(
          '/api/v1/location-ha-sensors/by-location/3/readings',
          (s) => s.reply(200, [
            {
              'id': 4,
              'name': 'Battery',
              'kind': 'numeric',
              'device_class': 'battery',
              'unit': '%',
              'state': '78',
              'value': 78.0,
              'reachable': false,
            },
          ]),
        );

        final reading = (await repo.readings(3)).single;

        expect(reading.reachable, isFalse);
        // The last known value is still the most useful thing to show.
        expect(reading.formattedValue, '78%');
      },
    );

    test('a 404 is an older server, not an error to show', () async {
      adapter.onGet(
        '/api/v1/location-ha-sensors/by-location/3/readings',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.readings(3), isEmpty);
    });
  });

  group('supportsLocationSensors', () {
    test('the version answers until the listing does', () async {
      replyVersion('1.2.5.4');
      expect(await repo.supportsLocationSensors(), isFalse);

      final newer = LocationSensorsRepository(dio, ServerVersionService(dio));
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': '1.2.6b1', 'repo': 'x/y'}),
      );
      expect(await newer.supportsLocationSensors(), isTrue);
    });

    test(
      'an unknown version keeps it off rather than asking and 404ing',
      () async {
        adapter.onGet(
          '/api/v1/updates/version',
          (s) => s.reply(500, {'detail': 'boom'}),
        );

        expect(await repo.supportsLocationSensors(), isFalse);
      },
    );

    test('with no version service at all it stays off', () async {
      expect(
        await LocationSensorsRepository(dio).supportsLocationSensors(),
        isFalse,
      );
    });

    test('a 404 outranks a version that claimed otherwise', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/location-ha-sensors/',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );
      expect(await repo.supportsLocationSensors(), isTrue);

      await repo.listBindings();

      expect(await repo.supportsLocationSensors(), isFalse);
    });

    test('a 403 hides it too, which no version could have said', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/location-ha-sensors/',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );

      await repo.listBindings();

      expect(await repo.supportsLocationSensors(), isFalse);
    });

    test(
      'a listing that came back says yes, whatever the version read',
      () async {
        adapter.onGet(
          '/api/v1/updates/version',
          (s) => s.reply(500, {'detail': 'boom'}),
        );
        adapter.onGet(
          '/api/v1/location-ha-sensors/',
          (s) => s.reply(200, const []),
        );

        await repo.listBindings();

        expect(await repo.supportsLocationSensors(), isTrue);
      },
    );
  });
}
