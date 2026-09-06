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

  /// Bez migawki stanu, którą start sesji dokłada zawsze (ma własny test niżej)
  /// — inaczej każdy asert o czymkolwiek innym musiałby ją omijać.
  Future<List<Map<String, dynamic>>> wsRecords() async =>
      (await allWsRecords()).where((r) => r['evt'] != 'state').toList();

  test('próba połączenia i jej czas: connect → open', () async {
    await recorder.start();
    probe.connecting(queryToken: true);
    tick(const Duration(milliseconds: 142));
    probe.opened();

    expect(await wsRecords(), [
      containsPair('evt', 'connect'),
      containsPair('evt', 'open'),
    ]);
  });

  test('connect niesie sposób auth, open czas handshake\'u', () async {
    await recorder.start();
    probe.connecting(queryToken: false);
    tick(const Duration(milliseconds: 142));
    probe.opened();

    final records = await wsRecords();
    expect(records.first['via'], 'header');
    expect(records.last['ms'], 142);
  });

  test('odrzucony handshake: status HTTP, przyczyna spod opakowania', () async {
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
    // Nazwa klasy jest już w `cause` — komunikat jej nie powtarza.
    expect(error['msg'], 'not upgraded to websocket');
  });

  test('nieudany mint tokenu: faza token, bez czasu handshake\'u', () async {
    await recorder.start();
    // Mint idzie przed jakąkolwiek próbą połączenia — samo żądanie loguje
    // `HttpProbe`, tutaj zostaje tylko wskazanie, na czym stanęło.
    probe.connectError(Exception('mint failed'), phase: 'token');

    final error = (await wsRecords()).single;
    expect(error['phase'], 'token');
    expect(error.containsKey('ms'), isFalse);
  });

  test('host serwera z komunikatu błędu jest zredagowany', () async {
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

  group('ramki', () {
    test('każda ramka to rekord z tym, co przyszło', () async {
      await recorder.start();
      probe.frame(
        _status(
          1,
          state: 'RUNNING',
          progress: 12.4,
          layer: 3,
          // Cokolwiek serwer przysłał, także targety i drugą dyszę — X2D/H2D ma
          // dwie, a target 0 w trakcie druku tłumaczy zgłoszenie sam z siebie.
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

    test('treść użytkownika z payloadu nie wchodzi do rekordu', () async {
      // To ta sama reguła co przy etykietach: log idzie do publicznego issue,
      // a `data` niesie nazwę modelu, nazwę pliku i serial drukarki.
      await recorder.start();
      probe.frame(
        WsPrinterStatus(
          PrinterStatus(
            id: 1,
            name: 'Drukarka Morgana',
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

    test('rekord pokrywa to, po czym serwer sam poznaje zmianę', () async {
      // `status_key` serwera to m.in. wentylatory, światło i aktywny slot —
      // bez nich `repeated` znaczyłoby „zmieniło się coś, na co nie patrzymy".
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

    test('AMS: materiał po zamkniętej liście, bez nazwy handlowej', () async {
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
                AmsTray(id: 1, remain: -1), // pusty slot, bez znacznika RFID
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
      // Nieznany materiał ma polec, a puste pola nie mają zostawiać nulli.
      expect((unit['trays'] as List).last, {'id': 1});
      // Wariant „Support W" jest na liście w całości, nie przycinany do bazy.
      expect((frame['vt'] as List).single['mat'], 'SUPPORT-W');
      // Nazwa handlowa i kolor to dane użytkownika — nie ma ich w rekordzie.
      final text = frame.toString();
      expect(text, isNot(contains('Professional')));
      expect(text, isNot(contains('F55A74')));
    });

    test('nieznany materiał w slocie nie przechodzi', () async {
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

    test('drukarka, która odpadła, mówi to wprost', () async {
      await recorder.start();
      probe.frame(_status(1, connected: false));
      probe.frame(_status(2, connected: true));

      final records = await wsRecords();
      expect(records.first['connected'], isFalse);
      // Przy działającej drukarce pole byłoby watą na każdym rekordzie.
      expect(records.last.containsKey('connected'), isFalse);
    });

    test('błędy HMS: ile stoi i które', () async {
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
      // Kod to szesnastkowy identyfikator z firmware'u, nie tekst użytkownika —
      // i redaktor nie może go wziąć za serial Bambu.
      expect(frame['hms_codes'], [
        '0300_0100_0002_0001',
        '0300_0100_0002_0002',
      ]);
      // Komunikat jest zlokalizowanym zdaniem serwera; do tego jest katalog.
      expect(frame.toString(), isNot(contains('Cooling fan')));
    });

    test('rozwścieczona drukarka nie zapcha linijki kodami', () async {
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
      expect(frame['hms'], 9); // licznik mówi prawdę o skali
      expect(frame['hms_codes'], hasLength(3));
    });

    test('ramka, która nic nie zmieniła, zwija się w licznik', () async {
      await recorder.start();
      // Serwer pcha przy zmianie własnego status_key — wentylatory, AMS
      // i światło też go zmieniają, a tych nie logujemy.
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

    test('zmiana choćby temperatury to nowy rekord', () async {
      await recorder.start();
      probe.frame(_status(1, state: 'RUNNING', temperatures: {'bed': 60.0}));
      probe.frame(_status(1, state: 'RUNNING', temperatures: {'bed': 61.0}));

      final records = await wsRecords();
      expect(records.map((r) => r['evt']), ['frame', 'frame']);
      expect(records.map((r) => r['bed']), [60, 61]);
    });

    test('długa seria melduje się co 5 s, a nie na końcu sesji', () async {
      await recorder.start();
      for (var i = 0; i < 30; i++) {
        tick(const Duration(seconds: 1));
        probe.frame(_status(1, state: 'IDLE'));
      }

      final records = await wsRecords();
      // Ten sam powód co przy burzy wyjątków (ErrorProbe): licznik dopisany
      // dopiero na końcu sesji nie mówi, kiedy pętla trwała.
      final repeats = records.where((r) => r['evt'] == 'repeated').toList();
      expect(repeats, hasLength(6)); // 5 okien po 5 + ogon 4 na stopie
      expect(records.where((r) => r['evt'] == 'frame'), hasLength(1));
      expect(
        repeats.fold<int>(0, (sum, r) => sum + (r['n'] as int)),
        29, // 1 rekord ramki + 29 zwiniętych = 30 ramek, co do jednej
      );
    });

    test('rozłączenie domyka serię przed swoim rekordem', () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      probe.opened();
      probe.frame(_status(1, state: 'IDLE'));
      probe.frame(_status(1, state: 'IDLE'));
      probe.disconnected(reason: WsDisconnectReason.remote, code: 1006);

      // Licznik należy do połączenia, które go wyprodukowało.
      expect((await wsRecords()).map((r) => r['evt']).toList(), [
        'connect',
        'open',
        'frame',
        'repeated',
        'disconnect',
      ]);
    });

    test('typy inne niż status też są rekordami', () async {
      await recorder.start();
      probe.frame(const WsUnknown('spoolbuddy_update'));
      probe.frame(const WsPlateNotEmpty(2, 'Drukarka Morgana', 'Plate busy'));
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
      // Zdarzenie mówi, czyja płyta — nie co serwer o niej napisał.
      expect(records[1]['printer_id'], 2);
      expect(records[1].toString(), isNot(contains('Morgan')));
      expect(records[2]['printer_id'], 3);
    });

    test('typ o dziwnym kształcie nie jedzie do logu dosłownie', () async {
      await recorder.start();
      probe.frame(const WsUnknown('Rain Gauge - Plate 5'));
      probe.frame(const WsUnknown(null));

      expect((await wsRecords()).map((r) => r['type']), ['other', 'untyped']);
    });

    test('seria sprzed nagrania nie wchodzi do sesji', () async {
      for (var i = 0; i < 5; i++) {
        probe.frame(_status(1, state: 'IDLE'));
      }

      await recorder.start();
      probe.frame(_status(1, state: 'IDLE'));
      probe.flushRepeats();

      // Bez zerowania licznik z poprzedniego życia dopisałby się do tej sesji.
      expect((await wsRecords()).map((r) => r['evt']), ['frame']);
    });
  });

  group('rozłączenie', () {
    test('kod, powód i czas życia połączenia', () async {
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

    test('zerwany strumień niesie klasę tego, co pękło', () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      probe.opened();
      probe.disconnected(
        reason: WsDisconnectReason.error,
        error: const FormatException('bad frame'),
      );

      expect((await wsRecords()).last['cause'], 'FormatException');
    });

    test('wejście w tło to nie awaria', () async {
      await recorder.start();
      probe.connecting(queryToken: true);
      probe.opened();
      probe.disconnected(reason: WsDisconnectReason.suspend);

      final close = (await wsRecords()).last;
      expect(close['reason'], 'suspend');
      expect(close.containsKey('lvl'), isFalse); // info
    });
  });

  test('kolejna próba: opóźnienie i numer próby', () async {
    await recorder.start();
    probe.retryScheduled(delay: const Duration(seconds: 2), attempt: 3);

    final retry = (await wsRecords()).single;
    expect(retry['evt'], 'retry');
    expect(retry['in_ms'], 2000);
    expect(retry['attempt'], 3);
  });

  test('bez nagrania sonda milczy', () async {
    probe.connecting(queryToken: true);
    probe.opened();
    probe.frame(_status(1));
    probe.disconnected(reason: WsDisconnectReason.remote, code: 1006);

    await recorder.start();
    expect(await wsRecords(), isEmpty);
  });

  group('migawka stanu na start sesji', () {
    test('sesja otwiera się tym, jak stoi połączenie', () async {
      // Tak jest w realnym przebiegu: socket wstał przy uruchomieniu apki,
      // a nagrywanie włącza się minuty później — `connect` i `open` to już
      // historia, więc bez migawki pierwszy dowód, że podgląd żyje, przychodzi
      // dopiero z pierwszym oknem ramek (na żywo: po 31 sekundach).
      probe.trackState('connected');
      probe.opened();
      tick(const Duration(minutes: 4));

      await recorder.start();

      final snapshot = (await allWsRecords()).single;
      expect(snapshot['evt'], 'state');
      expect(snapshot['state'], 'connected');
      expect(snapshot['up_ms'], const Duration(minutes: 4).inMilliseconds);
    });

    test('bez otwartego socketu migawka nie wymyśla czasu życia', () async {
      probe.trackState('waitingRetry');

      await recorder.start();

      final snapshot = (await allWsRecords()).single;
      expect(snapshot['state'], 'waitingRetry');
      expect(snapshot.containsKey('up_ms'), isFalse);
    });
  });
}
