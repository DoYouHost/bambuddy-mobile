import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/notifications/low_stock_feed.dart';
import 'package:bambuddy_mobile/features/notifications/low_stock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spools = [
    Spool(id: 7, material: 'PLA', labelWeight: 1000, weightUsed: 900),
  ];
  const assignments = [
    SpoolAssignment(spoolId: 7, printerId: 1, amsId: 0, trayId: 2),
  ];

  late List<Map<LowStockKey, LowStockSlot>> delivered;
  late int unavailable;

  LowStockFeed feed(Future<LowStockRead> Function() read) {
    delivered = [];
    unavailable = 0;
    return LowStockFeed(
      read: read,
      onSlots: delivered.add,
      onUnavailable: () => unavailable++,
    );
  }

  Future<LowStockRead> answers([Map<String, dynamic> settings = const {}]) =>
      Future.value((
        spools: spools,
        assignments: assignments,
        settings: settings,
      ));

  test('a look delivers the slots, against the server\'s threshold', () async {
    await feed(() => answers({'low_stock_threshold': 5})).refresh();
    expect(delivered.single.values.single.threshold, 5);
    expect(delivered.single.values.single.percent, 10);
  });

  test('and against 20 when the server does not say', () async {
    await feed(answers).refresh();
    expect(delivered.single.values.single.threshold, 20);
  });

  test(
    'a refusal or a missing route says the inventory is unavailable',
    () async {
      for (final error in const <AppApiException>[
        AuthException(AppErrorCode.forbidden),
        ApiException(AppErrorCode.badResponse, statusCode: 404),
      ]) {
        await feed(() => Future.error(error)).refresh();
        expect(unavailable, 1, reason: '$error');
        expect(delivered, isEmpty);
      }
    },
  );

  test('a failure that is not a refusal says nothing', () async {
    for (final error in const <AppApiException>[
      NetworkException(AppErrorCode.serverUnreachable),
      ApiException(AppErrorCode.badResponse, statusCode: 500),
      AuthException(AppErrorCode.unauthorized),
    ]) {
      await feed(() => Future.error(error)).refresh();
      expect(unavailable, 0, reason: '$error');
      expect(delivered, isEmpty);
    }
  });

  test('a bug in the read is not swallowed', () async {
    await expectLater(
      feed(() => Future.error(StateError('bug'))).refresh(),
      throwsStateError,
    );
  });

  test('looks that overlap are one in flight and one after', () async {
    final gate = Completer<void>();
    var reads = 0;
    final f = feed(() async {
      reads++;
      if (reads == 1) await gate.future;
      return answers();
    });
    final first = f.refresh();
    // Three more while the first is out: they collapse into a single follow-up.
    await f.refresh();
    await f.refresh();
    await f.refresh();
    expect(reads, 1);
    gate.complete();
    await first;
    expect(reads, 2);
    expect(delivered, hasLength(2));
  });

  test('a stopped feed neither delivers nor looks again', () async {
    final gate = Completer<void>();
    var reads = 0;
    final f = feed(() async {
      reads++;
      await gate.future;
      return answers();
    });
    final look = f.refresh();
    await f.refresh(); // queues one more
    f.stop();
    gate.complete();
    await look;
    expect(delivered, isEmpty);
    expect(reads, 1);
    await f.refresh();
    expect(reads, 1, reason: 'nothing starts after stop');
  });

  test('a look that failed does not leave the feed stuck', () async {
    var fail = true;
    final f = feed(
      () => fail
          ? Future.error(const NetworkException(AppErrorCode.serverUnreachable))
          : answers(),
    );
    await f.refresh();
    fail = false;
    await f.refresh();
    expect(delivered, hasLength(1));
  });

  group('over a server', () {
    // A server that answers by path, and a settings route that may refuse.
    Dio server({
      required int settingsStatus,
      Map<String, dynamic> settings = const {},
      Map<String, dynamic> flags = const {},
    }) {
      final dio = Dio(BaseOptions(baseUrl: 'http://server.test'));
      dio.httpClientAdapter = _Routes({
        '/api/v1/spoolman/status': (200, {'enabled': false}),
        '/api/v1/inventory/spools': (
          200,
          [
            {
              'id': 7,
              'material': 'PLA',
              'label_weight': 1000,
              'weight_used': 900,
            },
          ],
        ),
        '/api/v1/inventory/assignments': (
          200,
          [
            {'spool_id': 7, 'printer_id': 1, 'ams_id': 0, 'tray_id': 2},
          ],
        ),
        '/api/v1/settings': (settingsStatus, settings),
        '/api/v1/settings/ui-flags': (200, flags),
      });
      return dio;
    }

    Future<double> thresholdSeen(Dio dio) async {
      late double seen;
      await LowStockFeed.overDio(
        dio,
        onSlots: (slots) => seen = slots.values.single.threshold,
        onUnavailable: () => fail('unavailable'),
      ).refresh();
      return seen;
    }

    test('reads the threshold from the settings', () async {
      expect(
        await thresholdSeen(
          server(settingsStatus: 200, settings: {'low_stock_threshold': 12.5}),
        ),
        12.5,
      );
    });

    test('and from the flags for a session that may not read them', () async {
      expect(
        await thresholdSeen(
          server(settingsStatus: 403, flags: {'low_stock_threshold': 7}),
        ),
        7,
      );
    });

    for (final (status, route) in [
      (403, '/api/v1/inventory/spools'),
      (403, '/api/v1/inventory/assignments'),
      (404, '/api/v1/inventory/spools'),
    ]) {
      test('$status on $route says the inventory is unavailable', () async {
        final dio = server(settingsStatus: 200);
        (dio.httpClientAdapter as _Routes).routes[route] = (status, const {});
        var unavailable = 0;
        await LowStockFeed.overDio(
          dio,
          onSlots: (_) => fail('slots'),
          onUnavailable: () => unavailable++,
        ).refresh();
        expect(unavailable, 1);
      });
    }

    test('a failure that is not a refusal leaves it undecided', () async {
      final dio = server(settingsStatus: 200);
      (dio.httpClientAdapter as _Routes)
          .routes['/api/v1/inventory/assignments'] = (
        500,
        const {},
      );
      await LowStockFeed.overDio(
        dio,
        onSlots: (_) => fail('slots'),
        onUnavailable: () => fail('unavailable'),
      ).refresh();
    });

    group('which spools it asks for', () {
      // A server that records every path it is asked for.
      (Dio, List<String>) recorded({required bool embedded}) {
        final dio = server(settingsStatus: 200);
        final routes = dio.httpClientAdapter as _Routes;
        if (embedded) {
          routes.routes['/api/v1/inventory/assignments'] = (
            200,
            [
              {
                'spool_id': 7,
                'printer_id': 1,
                'ams_id': 0,
                'tray_id': 2,
                'spool': {
                  'id': 7,
                  'material': 'PLA',
                  'label_weight': 1000,
                  'weight_used': 900,
                },
              },
            ],
          );
        }
        return (dio, routes.asked);
      }

      test(
        'an assignment that carries its spool needs no list of spools',
        () async {
          final (dio, asked) = recorded(embedded: true);
          double? threshold;
          await LowStockFeed.overDio(
            dio,
            onSlots: (slots) => threshold = slots.values.single.percent,
            onUnavailable: () => fail('unavailable'),
          ).refresh();
          expect(threshold, 10);
          expect(asked, isNot(contains('/api/v1/inventory/spools')));
        },
      );

      test(
        'one that does not (Spoolman\'s) is read against the list',
        () async {
          final (dio, asked) = recorded(embedded: false);
          double? threshold;
          await LowStockFeed.overDio(
            dio,
            onSlots: (slots) => threshold = slots.values.single.percent,
            onUnavailable: () => fail('unavailable'),
          ).refresh();
          expect(threshold, 10);
          expect(asked, contains('/api/v1/inventory/spools'));
        },
      );

      test('a mix keeps the spools it was given and adds the list', () async {
        final dio = server(settingsStatus: 200);
        final routes = dio.httpClientAdapter as _Routes;
        routes.routes['/api/v1/inventory/assignments'] = (
          200,
          [
            {
              'spool_id': 7,
              'printer_id': 1,
              'ams_id': 0,
              'tray_id': 2,
              'spool': {
                'id': 7,
                'material': 'PLA',
                'label_weight': 1000,
                'weight_used': 900,
              },
            },
            // No spool inside, and not in the list either.
            {'spool_id': 8, 'printer_id': 1, 'ams_id': 0, 'tray_id': 3},
          ],
        );
        routes.routes['/api/v1/inventory/spools'] = (200, const []);
        late Map<LowStockKey, LowStockSlot> slots;
        await LowStockFeed.overDio(
          dio,
          onSlots: (s) => slots = s,
          onUnavailable: () => fail('unavailable'),
        ).refresh();
        expect(slots.keys.map((k) => k.spoolId), [7]);
        expect(routes.asked, contains('/api/v1/inventory/spools'));
      });

      test(
        'with nothing assigned there is nothing to read the list for',
        () async {
          final dio = server(settingsStatus: 200);
          final routes = dio.httpClientAdapter as _Routes;
          routes.routes['/api/v1/inventory/assignments'] = (200, const []);
          await LowStockFeed.overDio(
            dio,
            onSlots: (slots) => expect(slots, isEmpty),
            onUnavailable: () => fail('unavailable'),
          ).refresh();
          expect(routes.asked, isNot(contains('/api/v1/inventory/spools')));
        },
      );
    });

    test('and is the server\'s 20 when neither says', () async {
      expect(await thresholdSeen(server(settingsStatus: 403)), 20);
    });
  });
}

/// Answers each path with a status and a JSON body.
class _Routes implements HttpClientAdapter {
  _Routes(this.routes);

  final Map<String, (int, Object)> routes;

  /// Every path asked for, in order.
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options.path);
    final (status, body) = routes[options.path] ?? (404, const {});
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
