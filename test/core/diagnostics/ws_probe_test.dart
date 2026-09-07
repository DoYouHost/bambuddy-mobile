import 'dart:convert';
import 'dart:io' show WebSocketException;

import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/diagnostics/ws_probe.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

WsMessage _status(
  int id, {
  String? state,
  double? progress,
  int? layer,
  Map<String, double>? temperatures,
  bool? connected,
  List<HmsError>? hms,
  int? coolingFan,
  bool? light,
  bool? doorOpen,
  int? trayNow,
  List<AmsUnit>? ams,
  List<AmsTray>? vtTray,
  Map<int, String>? switchInlet,
}) => WsPrinterStatus(
  PrinterStatus(
    id: id,
    state: state,
    progress: progress,
    layerNum: layer,
    temperatures: temperatures,
    connected: connected,
    hmsErrors: hms,
    coolingFanSpeed: coolingFan,
    chamberLight: light,
    doorOpen: doorOpen,
    trayNow: trayNow,
    ams: ams,
    vtTray: vtTray,
    amsSwitchInlet: switchInlet,
  ),
  <String, dynamic>{'id': id},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const host = 's.local';

  late DiagnosticRecorder recorder;
  late WsProbe probe;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async => SessionFacts(
        app: '0.11.2+1102',
        flavor: 'mobile',
        secrets: const {host: '[HOST]'},
      ),
      resolveDirectory: () async => null,
    );
    now = DateTime.utc(2026, 7, 26, 12);
    probe = WsProbe(clock: () => now);
    addTearDown(probe.dispose);
    addTearDown(recorder.discard);
  });

  void tick(Duration d) => now = now.add(d);

  Future<List<Map<String, dynamic>>> allWsRecords() async {
    final jsonl = await recorder.stop();
    return [
      for (final line in const LineSplitter().convert(jsonl))
        if (jsonDecode(line) case final Map<String, dynamic> row
            when row['src'] == 'ws')
          row,
    ];
  }

  /// Without the state snapshot, which session start always adds (has its own
  /// test below) — otherwise every assertion about anything else would have
  /// to work around it.
  Future<List<Map<String, dynamic>>> wsRecords() async =>
      (await allWsRecords()).where((r) => r['evt'] != 'state').toList();

  test('connection attempt and its timing: connect → open', () async {
    await recorder.start();
    probe.connecting(queryToken: true);
    tick(const Duration(milliseconds: 142));
    probe.opened();

    expect(await wsRecords(), [
      containsPair('evt', 'connect'),
      containsPair('evt', 'open'),
    ]);
  });

  test('connect carries the auth method, open the handshake time', () async {
    await recorder.start();
    probe.connecting(queryToken: false);
    tick(const Duration(milliseconds: 142));
    probe.opened();

    final records = await wsRecords();
    expect(records.first['via'], 'header');
    expect(records.last['ms'], 142);
  });

  test(
    'rejected handshake: HTTP status, cause from under the wrapper',
    () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      tick(const Duration(milliseconds: 30));
      final rejected = WebSocketException('not upgraded to websocket', 401);
      probe.connectError(
        wsInnerError(rejected),
        phase: 'handshake',
        status: wsHandshakeStatus(rejected),
      );

      final error = (await wsRecords()).last;
      expect(error['evt'], 'connect_error');
      expect(error['lvl'], 'error');
      expect(error['phase'], 'handshake');
      expect(error['status'], 401);
      expect(error['cause'], 'WebSocketException');
      expect(error['ms'], 30);
      // The class name is already in `cause` — the message doesn't repeat it.
      expect(error['msg'], 'not upgraded to websocket');
    },
  );

  test('failed token mint: token phase, no handshake time', () async {
    await recorder.start();
    // Minting happens before any connection attempt — the request itself is
    // logged by `HttpProbe`, here only the point of failure remains.
    probe.connectError(Exception('mint failed'), phase: 'token');

    final error = (await wsRecords()).single;
    expect(error['phase'], 'token');
    expect(error.containsKey('ms'), isFalse);
  });

  test('server host in the error message is redacted', () async {
    await recorder.start();
    probe.connecting(queryToken: false);
    probe.connectError(
      Exception("Failed host lookup: '$host'"),
      phase: 'handshake',
    );

    final msg = (await wsRecords()).last['msg'] as String;
    expect(msg, contains('[HOST]'));
    expect(msg, isNot(contains(host)));
  });

  group('frames', () {
    test('every frame is a record of what came in', () async {
      await recorder.start();
      probe.frame(
        _status(
          1,
          state: 'RUNNING',
          progress: 12.4,
          layer: 3,
          // Whatever the server sent, including targets and the second nozzle —
          // X2D/H2D has two, and a target of 0 mid-print explains the report on its own.
          temperatures: {
            'nozzle': 218.3,
            'nozzle_target': 220.0,
            'nozzle_2': 140.0,
            'bed': 60.0,
            'bed_target': 0.0,
            'chamber': 33.4,
          },
        ),
      );

      final frame = (await wsRecords()).single;
      expect(frame['evt'], 'frame');
      expect(frame['type'], 'printer_status');
      expect(frame['printer_id'], 1);
      expect(frame['state'], 'RUNNING');
      expect(frame['progress'], 12);
      expect(frame['layer'], 3);
      expect(frame['nozzle'], 218);
      expect(frame['nozzle_target'], 220);
      expect(frame['nozzle_2'], 140);
      expect(frame['bed'], 60);
      expect(frame['bed_target'], 0);
      expect(frame['chamber'], 33);
    });

    test('user content from the payload does not enter the record', () async {
      // Same rule as with labels: the log goes into a public issue, and
      // `data` carries the model name, filename and printer serial.
      await recorder.start();
      probe.frame(
        WsPrinterStatus(
          PrinterStatus(
            id: 1,
            name: "Morgan's Printer",
            gcodeFile: 'Rain Gauge - Plate 5.gcode.3mf',
            currentPrint: 'Rain Gauge',
            coverUrl: '/api/v1/printers/1/cover',
            model: 'X1C',
          ),
          const {'id': 1},
        ),
      );

      final frame = (await wsRecords()).single.toString();
      expect(frame, isNot(contains('Rain Gauge')));
      expect(frame, isNot(contains('Morgan')));
      expect(frame, isNot(contains('cover')));
    });

    test('the record covers what the server itself keys change on', () async {
      // The server's `status_key` includes fans, light and the active slot —
      // without them `repeated` would mean "something changed that we don't watch".
      await recorder.start();
      probe.frame(
        _status(
          1,
          state: 'RUNNING',
          coolingFan: 100,
          light: true,
          doorOpen: true,
          trayNow: 2,
        ),
      );

      final frame = (await wsRecords()).single;
      expect(frame['cooling_fan'], 100);
      expect(frame['light'], isTrue);
      expect(frame['door_open'], isTrue);
      expect(frame['tray_now'], 2);
    });

    test(
      'the switch inlet binding is recorded only when one is fitted',
      () async {
        // Without a Filament Track Switch the field is on every frame of every
        // session and says nothing; with one it is the only thing that explains
        // which nozzle a slot was configured against.
        await recorder.start();
        probe.frame(_status(1, state: 'RUNNING'));
        probe.frame(
          _status(1, state: 'IDLE', switchInlet: const {1: 'B', 0: 'A'}),
        );

        final frames = await wsRecords();
        expect(frames.first.containsKey('fts_inlet'), isFalse);
        expect(frames.last['fts_inlet'], '0:A,1:B');
      },
    );

    test('AMS: material from the closed list, no brand name', () async {
      await recorder.start();
      probe.frame(
        _status(
          1,
          ams: const [
            AmsUnit(
              id: 0,
              humidity: 22,
              dryStatus: 2,
              dryTime: 45,
              trays: [
                AmsTray(
                  id: 0,
                  trayType: 'PETG',
                  traySubBrands: 'Professional Lab PETG Basic',
                  trayColor: 'F55A74FF',
                  remain: 83,
                ),
                AmsTray(id: 1, remain: -1), // empty slot, no RFID tag
              ],
            ),
          ],
          vtTray: const [AmsTray(id: 254, trayType: 'Support W', remain: 100)],
        ),
      );

      final frame = (await wsRecords()).single;
      final unit = (frame['ams'] as List).single as Map<String, dynamic>;
      expect(unit['rh'], 22);
      expect(unit['dry'], 2);
      expect(unit['dry_min'], 45);
      expect((unit['trays'] as List).first, {
        'id': 0,
        'mat': 'PETG',
        'remain': 83,
      });
      // An unknown material should drop, and empty fields must not leave nulls.
      expect((unit['trays'] as List).last, {'id': 1});
      // The "Support W" variant is on the list in full, not trimmed to its base.
      expect((frame['vt'] as List).single['mat'], 'SUPPORT-W');
      // Brand name and color are user data — they are not in the record.
      final text = frame.toString();
      expect(text, isNot(contains('Professional')));
      expect(text, isNot(contains('F55A74')));
    });

    test('an unknown material in a slot does not pass through', () async {
      await recorder.start();
      probe.frame(
        _status(
          1,
          ams: const [
            AmsUnit(id: 0, trays: [AmsTray(id: 0, trayType: 'PLA-WOOD')]),
          ],
        ),
      );

      final unit = ((await wsRecords()).single['ams'] as List).single;
      expect((unit as Map)['trays'], [
        {'id': 0},
      ]);
    });

    test('a printer that dropped off says so outright', () async {
      await recorder.start();
      probe.frame(_status(1, connected: false));
      probe.frame(_status(2, connected: true));

      final records = await wsRecords();
      expect(records.first['connected'], isFalse);
      // For a working printer the field would be padding on every record.
      expect(records.last.containsKey('connected'), isFalse);
    });

    test('HMS errors: how many stand and which ones', () async {
      await recorder.start();
      probe.frame(
        _status(
          1,
          hms: [
            const HmsError(code: '0300_0100_0002_0001'),
            const HmsError(code: '0300_0100_0002_0002', message: 'Cooling fan'),
          ],
        ),
      );

      final frame = (await wsRecords()).single;
      expect(frame['hms'], 2);
      // The code is a hex identifier from the firmware, not user text —
      // and the redactor must not mistake it for a Bambu serial.
      expect(frame['hms_codes'], [
        '0300_0100_0002_0001',
        '0300_0100_0002_0002',
      ]);
      // The message is the server's localized sentence; there's a catalog for it.
      expect(frame.toString(), isNot(contains('Cooling fan')));
    });

    test('a furious printer does not flood the line with codes', () async {
      await recorder.start();
      probe.frame(
        _status(
          1,
          hms: [
            for (var i = 0; i < 9; i++) HmsError(code: '0300_0100_0002_000$i'),
          ],
        ),
      );

      final frame = (await wsRecords()).single;
      expect(frame['hms'], 9); // the counter tells the truth about scale
      expect(frame['hms_codes'], hasLength(3));
    });

    test('a frame that changed nothing collapses into a counter', () async {
      await recorder.start();
      // The server pushes when its own status_key changes — fans, AMS
      // and light also change it, and we don't log those.
      for (var i = 0; i < 5; i++) {
        probe.frame(_status(1, state: 'IDLE'));
      }
      probe.frame(const WsPong());

      final records = await wsRecords();
      expect(records.map((r) => r['evt']), ['frame', 'repeated', 'frame']);
      expect(records[1]['type'], 'printer_status');
      expect(records[1]['n'], 4);
      expect(records.last['type'], 'pong');
    });

    test('even a temperature change is a new record', () async {
      await recorder.start();
      probe.frame(_status(1, state: 'RUNNING', temperatures: {'bed': 60.0}));
      probe.frame(_status(1, state: 'RUNNING', temperatures: {'bed': 61.0}));

      final records = await wsRecords();
      expect(records.map((r) => r['evt']), ['frame', 'frame']);
      expect(records.map((r) => r['bed']), [60, 61]);
    });

    test('a long series reports every 5s, not just at session end', () async {
      await recorder.start();
      for (var i = 0; i < 30; i++) {
        tick(const Duration(seconds: 1));
        probe.frame(_status(1, state: 'IDLE'));
      }

      final records = await wsRecords();
      // Same reason as with the exception storm (ErrorProbe): a counter
      // appended only at session end doesn't say when the loop was running.
      final repeats = records.where((r) => r['evt'] == 'repeated').toList();
      expect(repeats, hasLength(6)); // 5 windows of 5 + a tail of 4 at stop
      expect(records.where((r) => r['evt'] == 'frame'), hasLength(1));
      expect(
        repeats.fold<int>(0, (sum, r) => sum + (r['n'] as int)),
        29, // 1 frame record + 29 collapsed = 30 frames, to the one
      );
    });

    test('a disconnect closes off the series before its own record', () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      probe.opened();
      probe.frame(_status(1, state: 'IDLE'));
      probe.frame(_status(1, state: 'IDLE'));
      probe.disconnected(reason: WsDisconnectReason.remote, code: 1006);

      // The counter belongs to the connection that produced it.
      expect((await wsRecords()).map((r) => r['evt']).toList(), [
        'connect',
        'open',
        'frame',
        'repeated',
        'disconnect',
      ]);
    });

    test('types other than status are also records', () async {
      await recorder.start();
      probe.frame(const WsUnknown('spoolbuddy_update'));
      probe.frame(const WsPlateNotEmpty(2, "Morgan's Printer", 'Plate busy'));
      probe.frame(const WsPrintEvent(3, completed: true));
      probe.frame(null);
      probe.binaryFrame();

      final records = await wsRecords();
      expect(records.map((r) => r['type']), [
        'spoolbuddy_update',
        'plate_not_empty',
        'print_complete',
        'unparsed',
        'binary',
      ]);
      // The event says whose plate — not what the server wrote about it.
      expect(records[1]['printer_id'], 2);
      expect(records[1].toString(), isNot(contains('Morgan')));
      expect(records[2]['printer_id'], 3);
    });

    test('a weirdly shaped type does not go into the log verbatim', () async {
      await recorder.start();
      probe.frame(const WsUnknown('Rain Gauge - Plate 5'));
      probe.frame(const WsUnknown(null));

      expect((await wsRecords()).map((r) => r['type']), ['other', 'untyped']);
    });

    test('a series from before recording does not enter the session', () async {
      for (var i = 0; i < 5; i++) {
        probe.frame(_status(1, state: 'IDLE'));
      }

      await recorder.start();
      probe.frame(_status(1, state: 'IDLE'));
      probe.flushRepeats();

      // Without resetting, the counter from a previous life would carry into this session.
      expect((await wsRecords()).map((r) => r['evt']), ['frame']);
    });
  });

  group('disconnect', () {
    test('code, reason and connection lifetime', () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      probe.opened();
      tick(const Duration(seconds: 42));
      probe.disconnected(
        reason: WsDisconnectReason.remote,
        code: 1001,
        closeReason: 'server shutting down',
      );

      final close = (await wsRecords()).last;
      expect(close['evt'], 'disconnect');
      expect(close['lvl'], 'warn');
      expect(close['reason'], 'remote');
      expect(close['code'], 1001);
      expect(close['close_reason'], 'server shutting down');
      expect(close['up_ms'], 42000);
    });

    test('a broken stream carries the class of what broke', () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      probe.opened();
      probe.disconnected(
        reason: WsDisconnectReason.error,
        error: const FormatException('bad frame'),
      );

      expect((await wsRecords()).last['cause'], 'FormatException');
    });

    test('going to the background is not a failure', () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      probe.opened();
      probe.disconnected(reason: WsDisconnectReason.suspend);

      final close = (await wsRecords()).last;
      expect(close['reason'], 'suspend');
      expect(close.containsKey('lvl'), isFalse); // info
    });
  });

  test('next attempt: delay and attempt number', () async {
    await recorder.start();
    probe.retryScheduled(delay: const Duration(seconds: 2), attempt: 3);

    final retry = (await wsRecords()).single;
    expect(retry['evt'], 'retry');
    expect(retry['in_ms'], 2000);
    expect(retry['attempt'], 3);
  });

  test('without recording the probe stays silent', () async {
    probe.connecting(queryToken: true);
    probe.opened();
    probe.frame(_status(1));
    probe.disconnected(reason: WsDisconnectReason.remote, code: 1006);

    await recorder.start();
    expect(await wsRecords(), isEmpty);
  });

  group('state snapshot at session start', () {
    test('a session opens with how the connection stands', () async {
      // This is how it works live: the socket came up when the app launched,
      // and recording turns on minutes later — `connect` and `open` are already
      // history, so without the snapshot the first proof the connection is
      // alive comes only with the first frame window (live: after 31 seconds).
      probe.trackState('connected');
      probe.opened();
      tick(const Duration(minutes: 4));

      await recorder.start();

      final snapshot = (await allWsRecords()).single;
      expect(snapshot['evt'], 'state');
      expect(snapshot['state'], 'connected');
      expect(snapshot['up_ms'], const Duration(minutes: 4).inMilliseconds);
    });

    test(
      'without an open socket the snapshot does not invent a lifetime',
      () async {
        probe.trackState('waitingRetry');

        await recorder.start();

        final snapshot = (await allWsRecords()).single;
        expect(snapshot['state'], 'waitingRetry');
        expect(snapshot.containsKey('up_ms'), isFalse);
      },
    );
  });
}
