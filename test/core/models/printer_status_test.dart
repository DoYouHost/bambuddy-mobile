import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('PrinterStatus.fromJson', () {
    test('parsuje status drukującej drukarki, ignorując nieznane pola', () {
      final status = PrinterStatus.fromJson(
          readFixture('printer_status_printing.json') as Map<String, dynamic>);

      expect(status.id, 1);
      expect(status.name, 'X1C Warsztat');
      expect(status.connected, isTrue);
      expect(status.state, 'RUNNING');
      expect(status.currentPrint, 'benchy.3mf');
      expect(status.gcodeFile, 'benchy_plate_1.gcode');
      expect(status.progress, 42.5);
      expect(status.remainingTime, 137);
      expect(status.layerNum, 87);
      expect(status.totalLayers, 203);
      expect(status.temperatures, {
        'nozzle': 219.7,
        'bed': 60.0,
        'chamber': 31.2,
      });
      expect(status.isPrinting, isTrue);
    });

    test('a real WS frame from a print start reports its stage', () {
      // The captured frame is a printer that has just been sent a job: RUNNING,
      // layer 0, 0%, and `stg_cur: 54` — "Waiting for heatbed temperature".
      // This is the frame the first-layer alert has to keep quiet through, and
      // proof that the number really does arrive on the WebSocket lane, where
      // `mc_print_sub_stage` never does.
      final frame = readFixture('ws_printer_status.json') as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(frame['data'] as Map);
      data['id'] = frame['printer_id'];
      final status = PrinterStatus.fromJson(data);

      expect(status.state, 'RUNNING');
      expect(status.layerNum, 0);
      expect(status.stgCur, 54);
      expect(status.inNamedStage, isTrue);
    });

    test('the stage number decides what a stage is, not its name', () {
      // `stg_cur_name` is derived server-side and says "Printing" at stage 0,
      // so a non-null name is no evidence of a stage. Both lanes carry the
      // number; the REST-only `mc_print_sub_stage` bambuddy reads is not an
      // option for the app.
      PrinterStatus parse(Object? stage) => PrinterStatus.fromJson(
          {'id': 1, 'stg_cur': stage, 'stg_cur_name': 'Printing'});

      expect(parse(0).stgCur, 0);
      expect(parse(0).inNamedStage, isFalse, reason: '0 is "Printing"');
      expect(parse(9).inNamedStage, isTrue, reason: '9 is scanning the bed');
      expect(parse(254).inNamedStage, isTrue);
      // The two idle codes: -1 on X1, 255 on A1/P1.
      expect(parse(-1).inNamedStage, isFalse);
      expect(parse(255).inNamedStage, isFalse);
      // A server that sends no number at all keeps the previous behaviour.
      expect(parse(null).stgCur, isNull);
      expect(parse(null).inNamedStage, isFalse);
      // Tolerant parsing like every other number here.
      expect(parse('9').stgCur, 9);
      expect(parse('nonsense').stgCur, isNull);
    });

    test('parsuje pola sterowania (wentylatory, prędkość, światło)', () {
      final status = PrinterStatus.fromJson(
          readFixture('printer_status_printing.json') as Map<String, dynamic>);

      expect(status.coolingFanSpeed, 53);
      expect(status.bigFan1Speed, 73);
      expect(status.bigFan2Speed, 60);
      expect(status.heatbreakFanSpeed, 0);
      expect(status.speedLevel, 2);
      expect(status.speedPercent, 100, reason: 'poziom 2 = Standard = 100%');
      expect(status.chamberLight, isTrue);
      expect(status.airductMode, 0);
      expect(status.airductIsHeating, isFalse, reason: '0 = chłodzenie');
    });

    test('airductIsHeating: 0 chłodzi, 1 grzeje, reszta null', () {
      bool? heat(int? m) => PrinterStatus(id: 1, airductMode: m).airductIsHeating;

      expect(heat(0), isFalse);
      expect(heat(1), isTrue);
      expect(heat(7), isNull);
      expect(heat(null), isNull);
    });

    test('speedPercent mapuje poziomy i zwraca null dla nieznanego', () {
      int? pct(int? level) => PrinterStatus(id: 1, speedLevel: level).speedPercent;

      expect(pct(1), 50);
      expect(pct(2), 100);
      expect(pct(3), 124);
      expect(pct(4), 166);
      expect(pct(9), isNull);
      expect(pct(null), isNull);
    });

    test('parsuje status bezczynnej drukarki', () {
      final status = PrinterStatus.fromJson(
          readFixture('printer_status_idle.json') as Map<String, dynamic>);

      expect(status.state, 'IDLE');
      expect(status.currentPrint, isNull);
      expect(status.isPrinting, isFalse);
    });

    test('toleruje liczby jako stringi i nieparsowalne wartości temperatur',
        () {
      final status = PrinterStatus.fromJson(
          readFixture('printer_status_error.json') as Map<String, dynamic>);

      expect(status.state, 'FAILED');
      expect(status.progress, 61.0, reason: 'progress przyszedł jako string');
      expect(status.remainingTime, 88);
      expect(status.layerNum, isNull);
      expect(status.temperatures, {'nozzle': 25.0},
          reason: '"off" nie jest liczbą — wpis pominięty, nie crash');
    });

    test('metadane czasu (chamber_target_set_time) pomijane w temperaturach',
        () {
      final status = PrinterStatus.fromJson(const {
        'id': 1,
        'temperatures': {
          'nozzle': 210,
          'chamber': 30,
          'chamber_target_set_time': 1751000000,
        },
      });

      expect(status.temperatures, {'nozzle': 210.0, 'chamber': 30.0},
          reason: 'klucz *_time to znacznik czasu, nie czujnik — nie kafelek');
    });

    test('minimalny payload (samo id) nie wywala parsera', () {
      final status = PrinterStatus.fromJson(const {'id': 7});

      expect(status.id, 7);
      expect(status.state, isNull);
      expect(status.temperatures, isNull);
      expect(status.isPrinting, isFalse);
    });

    test('faza przygotowania (RUNNING, progress 0) liczy się jako wydruk', () {
      const status = PrinterStatus(
        id: 1,
        state: 'RUNNING',
        progress: 0,
        remainingTime: 0,
        stgCurName: 'Auto bed leveling',
      );

      expect(status.isPrinting, isTrue,
          reason: 'nagrzewanie/leveling to etap wydruku');
      expect(status.isPreparing, isTrue);
    });

    test('FAILED nie jest wydrukiem mimo dodatniego progresu', () {
      const status =
          PrinterStatus(id: 1, state: 'FAILED', progress: 61, remainingTime: 88);

      expect(status.isPrinting, isFalse);
    });
  });

  group('AMS / sloty filamentu', () {
    PrinterStatus realStatus() {
      final frame = readFixture('ws_printer_status.json') as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(frame['data'] as Map);
      data['id'] = frame['printer_id'];
      return PrinterStatus.fromJson(data);
    }

    test('parsuje jednostkę AMS z slotami i pomiarami', () {
      final status = realStatus();

      expect(status.ams, hasLength(1));
      final unit = status.ams!.first;
      expect(unit.id, 0);
      expect(unit.humidity, 28);
      expect(unit.temp, 31.0, reason: 'temp przyszła jako string "31.0"');
      expect(unit.trays, hasLength(4));

      final tray0 = unit.trays![0];
      expect(tray0.id, 0);
      expect(tray0.trayType, 'PETG');
      expect(tray0.trayColor, 'FFFFFFFF');
      expect(tray0.remain, -1, reason: 'brak tagu RFID → nieznana ilość');

      final tray3 = unit.trays![3];
      expect(tray3.trayType, 'PLA');
      expect(tray3.traySubBrands, 'PLA Basic');
      expect(tray3.remain, 66);
      expect(tray3.materialLabel, 'PLA Basic',
          reason: 'wariant marki ma pierwszeństwo przed surowym typem');
    });

    test('parsuje szpulę zewnętrzną (vt_tray) i tray_now/model', () {
      final status = realStatus();

      expect(status.vtTray, hasLength(2));
      expect(status.vtTray!.first.id, 254);
      expect(status.vtTray!.first.trayType, 'TPU');
      expect(status.trayNow, 2);
      expect(status.model, 'X2D');
      expect(status.wifiSignal, -59);
      expect(status.doorOpen, isFalse);
      expect(status.hasDetails, isTrue);
    });

    test('AmsTray.isEmpty: brak materiału lub przezroczysty kolor', () {
      expect(const AmsTray(trayType: 'PLA', trayColor: '000000FF').isEmpty,
          isFalse);
      expect(const AmsTray(trayType: '', trayColor: '000000FF').isEmpty, isTrue,
          reason: 'pusty typ = pusty slot');
      expect(const AmsTray(trayType: null).isEmpty, isTrue);
      expect(const AmsTray(trayType: 'PLA', trayColor: '00000000').isEmpty,
          isTrue,
          reason: 'alpha 00 = w pełni przezroczysty = pusty');
    });

    test('odporność: nie-lista AMS i element nie-mapowy nie wywracają parsera',
        () {
      final status = PrinterStatus.fromJson(const {
        'id': 1,
        'ams': 'nonsense',
        'vt_tray': [
          {'id': 254, 'tray_type': 'PLA'},
          'junk',
        ],
      });

      expect(status.ams, isNull, reason: 'AMS nie-lista → null, nie crash');
      expect(status.vtTray, hasLength(1),
          reason: 'element nie-mapowy pominięty');
    });

    test('brak danych AMS → hasDetails false', () {
      expect(const PrinterStatus(id: 1).hasDetails, isFalse);
    });

    test('parsuje active_extruder i ams_extruder_map (klucze-stringi)', () {
      final status = realStatus();
      expect(status.activeExtruder, 1);
      expect(status.amsExtruderMap, {0: 1});
      expect(status.isDualExtruder, isTrue,
          reason: 'dwie szpule zewnętrzne → maszyna dwudyszowa');
    });

    test('externalSpools sortuje po id rosnąco', () {
      final status = realStatus();
      final spools = status.externalSpools;
      expect(spools.map((t) => t.id), [254, 255]);
      expect(spools.map((t) => t.trayType), ['TPU', 'PLA']);
    });

    // Potwierdzone przy fizycznej drukarce: 254 (TPU) na lewym (ekstruder 1),
    // 255 (PLA) na prawym (ekstruder 0) — odwrotnie do kolejności id.
    test('extruderForExternal mapuje odwrotnie do id', () {
      final status = realStatus();
      expect(status.extruderForExternal(254), 1, reason: '254 → lewy (ext 1)');
      expect(status.extruderForExternal(255), 0, reason: '255 → prawy (ext 0)');
      expect(status.extruderForExternal(999), isNull);
    });

    test('activeTray: tray_now w AMS wskazuje slot tej jednostki', () {
      final status = realStatus(); // tray_now=2 → AMS0 slot 2 (PETG)
      expect(status.activeTray?.trayType, 'PETG');
      expect(identical(status.activeTray, status.ams!.first.trays![2]), isTrue);
    });

    // Sedno zgłoszonego błędu: na szpuli zewnętrznej liczy się materiał
    // aktywnego ekstrudera, nie pierwszy z listy.
    test('activeTray: szpula zewnętrzna → materiał AKTYWNEGO ekstrudera', () {
      const tpu = AmsTray(id: 254, trayType: 'TPU', trayColor: '0ACC38FF');
      const pla = AmsTray(id: 255, trayType: 'PLA', trayColor: '91202BFF');

      // active_extruder=1 (lewy) → TPU (254 mapuje się na lewy ekstruder).
      const onExt1 = PrinterStatus(
        id: 1,
        trayNow: 254,
        activeExtruder: 1,
        vtTray: [tpu, pla],
      );
      expect(onExt1.activeTray?.trayType, 'TPU');

      // active_extruder=0 (prawy) → PLA (255 mapuje się na prawy ekstruder).
      const onExt0 = PrinterStatus(
        id: 1,
        trayNow: 254,
        activeExtruder: 0,
        vtTray: [tpu, pla],
      );
      expect(onExt0.activeTray?.trayType, 'PLA');
    });
  });

  group('PrinterStatus.mergedWith', () {
    test('ramka WS (bez airduct) dziedziczy tryb komory z poprzedniego pollu', () {
      // Poll dał tryb komory (REST), ale następna ramka WS go nie niesie.
      const fromPoll = PrinterStatus(id: 1, state: 'RUNNING', airductMode: 1);
      const fromWs = PrinterStatus(id: 1, state: 'RUNNING', progress: 50);

      final merged = fromWs.mergedWith(fromPoll);
      expect(merged.airductMode, 1); // przeniesione → chip nie miga
      expect(merged.progress, 50); // żywe pole bierze świeżą wartość z WS
    });

    test('poll (bez pól WS) dziedziczy model/cover/szpulę z poprzedniej ramki WS',
        () {
      const fromWs = PrinterStatus(
        id: 1,
        model: 'X2D',
        coverUrl: 'http://c/cover.png',
        doorOpen: true,
        wifiSignal: -55,
      );
      const fromPoll = PrinterStatus(id: 1, state: 'RUNNING', airductMode: 0);

      final merged = fromPoll.mergedWith(fromWs);
      expect(merged.model, 'X2D');
      expect(merged.coverUrl, 'http://c/cover.png');
      expect(merged.doorOpen, isTrue);
      expect(merged.wifiSignal, -55);
      expect(merged.airductMode, 0); // świeże z pollu zostaje
    });

    test('świeża wartość ma pierwszeństwo nad poprzednią (nie nadpisuje nullem)',
        () {
      const prev = PrinterStatus(id: 1, airductMode: 1, model: 'X2D');
      const fresh = PrinterStatus(id: 1, airductMode: 0, model: 'P1S');
      final merged = fresh.mergedWith(prev);
      expect(merged.airductMode, 0);
      expect(merged.model, 'P1S');
    });

    test('previous == null → zwraca siebie', () {
      const s = PrinterStatus(id: 1, state: 'IDLE');
      expect(identical(s.mergedWith(null), s), isTrue);
    });

    test('częściowy poll (żywe pola null) dziedziczy ostatnią znaną wartość', () {
      // Bootująca się drukarka: poprzedni snapshot miał komplet, następny gubi
      // postęp/temperatury/wentylator — nie wolno ich wygasić do `—`.
      const prev = PrinterStatus(
        id: 1,
        state: 'RUNNING',
        progress: 40,
        remainingTime: 88,
        coolingFanSpeed: 60,
        temperatures: {'nozzle': 210.0},
      );
      const partial = PrinterStatus(id: 1, state: 'RUNNING');

      final merged = partial.mergedWith(prev);
      expect(merged.progress, 40);
      expect(merged.remainingTime, 88);
      expect(merged.coolingFanSpeed, 60);
      expect(merged.temperatures, {'nozzle': 210.0});
    });

    test('temperatury scalają się per-klucz (brak czujnika nie gasi kafelka)', () {
      const prev =
          PrinterStatus(id: 1, temperatures: {'nozzle': 200.0, 'bed': 60.0});
      // Następna ramka niesie tylko świeżą dyszę — stół musi zostać.
      const fresh = PrinterStatus(id: 1, temperatures: {'nozzle': 205.0});

      final merged = fresh.mergedWith(prev);
      expect(merged.temperatures, {'nozzle': 205.0, 'bed': 60.0});
    });

    test('connected:false propaguje się mimo reguły dziedziczenia', () {
      const prev = PrinterStatus(id: 1, connected: true);
      const fresh = PrinterStatus(id: 1, connected: false);
      expect(fresh.mergedWith(prev).connected, isFalse);
    });

    test('offline gasi żywą telemetrię (backend niesie stary cache)', () {
      // Drukarka drukowała, potem padła: backend flipuje connected:false, ale
      // NIE czyści stanu — ramka niesie stary RUNNING/postęp/temperatury.
      const prev = PrinterStatus(
        id: 1,
        connected: true,
        state: 'RUNNING',
        progress: 60,
        remainingTime: 42,
        gcodeFile: 'benchy.gcode',
        coverUrl: 'http://c/cover.png',
        temperatures: {'nozzle': 210.0, 'bed': 60.0},
        coolingFanSpeed: 70,
        chamberLight: true,
      );
      const offline = PrinterStatus(
        id: 1,
        connected: false,
        state: 'RUNNING', // serwer trzyma ostatni stan mimo rozłączenia
        progress: 60,
        temperatures: {'nozzle': 208.0},
      );

      final merged = offline.mergedWith(prev);
      expect(merged.connected, isFalse);
      expect(merged.state, isNull); // brak żywego stanu → OFFLINE, nie RUNNING
      expect(merged.isPrinting, isFalse);
      expect(merged.progress, isNull);
      expect(merged.remainingTime, isNull);
      expect(merged.gcodeFile, isNull);
      expect(merged.coverUrl, isNull);
      expect(merged.temperatures, isNull);
      expect(merged.coolingFanSpeed, isNull);
      expect(merged.chamberLight, isNull);
    });

    test('offline zachowuje tożsamość, sprzęt, magazyn AMS i hms_errors', () {
      const prev = PrinterStatus(
        id: 1,
        connected: true,
        name: 'X2D',
        model: 'X2D',
        supportsDrying: true,
        ams: [AmsUnit(id: 0)],
        hmsErrors: [HmsError(code: '0300')],
      );
      const offline = PrinterStatus(id: 1, connected: false);

      final merged = offline.mergedWith(prev);
      expect(merged.name, 'X2D');
      expect(merged.model, 'X2D');
      expect(merged.supportsDrying, isTrue);
      expect(merged.ams, isNotNull);
      // hms_errors przenoszone: PrintMonitor pauzuje na nich zegar clear-grace.
      expect(merged.hmsErrors, isNotNull);
    });

    test('the stage number is dropped when the printer goes offline', () {
      // Live telemetry, unlike the plate gate below: a printer nobody can reach
      // is not levelling its bed, and a stale stage would keep the first-layer
      // and milestone gates shut for a print that starts after it wakes.
      const prev = PrinterStatus(id: 1, connected: true, stgCur: 9);
      const offline = PrinterStatus(id: 1, connected: false);

      expect(prev.inNamedStage, isTrue);
      expect(offline.mergedWith(prev).stgCur, isNull);
      expect(offline.mergedWith(prev).inNamedStage, isFalse);
    });

    test('the plate-clear gate survives the printer going offline', () {
      // Not telemetry: the gate is bambuddy's own flag, persisted so it outlives
      // the printer being switched off. Under Auto Power Off that is how every
      // print ends, and dropping the flag here hid the only control that
      // releases it (server #2864).
      const prev =
          PrinterStatus(id: 1, connected: true, awaitingPlateClear: true);
      const offline =
          PrinterStatus(id: 1, connected: false, awaitingPlateClear: true);

      expect(offline.mergedWith(prev).awaitingPlateClear, isTrue);
      // Same normalisation with nothing to merge onto (first frame after start).
      expect(offline.mergedWith(null).awaitingPlateClear, isTrue);
      // The server releasing the gate still propagates — this is not stickiness.
      const cleared =
          PrinterStatus(id: 1, connected: false, awaitingPlateClear: false);
      expect(cleared.mergedWith(prev).awaitingPlateClear, isFalse);
    });

    test('powrót online repopuluje telemetrię ze świeżej ramki', () {
      const offline = PrinterStatus(id: 1, connected: false, model: 'P1S');
      const online = PrinterStatus(
        id: 1,
        connected: true,
        state: 'RUNNING',
        progress: 5,
        temperatures: {'nozzle': 200.0},
      );

      final merged = online.mergedWith(offline);
      expect(merged.connected, isTrue);
      expect(merged.state, 'RUNNING');
      expect(merged.progress, 5);
      expect(merged.temperatures, {'nozzle': 200.0});
      expect(merged.model, 'P1S'); // sprzęt przetrwał przerwę
    });

    test('zmiana pliku (wejście w kalibrację) NIE dziedziczy starej okładki', () {
      // Drukował model z okładką, teraz wchodzi w kalibrację bez własnej okładki
      // — podgląd poprzedniego modelu nie może się przenieść.
      const prev = PrinterStatus(
        id: 1,
        state: 'RUNNING',
        gcodeFile: 'benchy.gcode',
        coverUrl: 'http://c/cover.png',
      );
      const cali = PrinterStatus(
        id: 1,
        state: 'RUNNING',
        gcodeFile: 'auto_cali_for_user_param.gcode',
      );
      expect(cali.mergedWith(prev).coverUrl, isNull);
    });

    test('ten sam plik bez cover_url (poll REST) dalej dziedziczy okładkę', () {
      const prev = PrinterStatus(
        id: 1,
        gcodeFile: 'benchy.gcode',
        coverUrl: 'http://c/cover.png',
      );
      const poll = PrinterStatus(id: 1, gcodeFile: 'benchy.gcode', progress: 30);
      expect(poll.mergedWith(prev).coverUrl, 'http://c/cover.png');
    });
  });

  group('Wentylatory akcesoryjne P2S/X2D', () {
    test('parsuje left_aux_fan_speed i exhaust_fan_present', () {
      final s = PrinterStatus.fromJson(const {
        'id': 1,
        'model': 'X2D',
        'left_aux_fan_speed': 40,
        'exhaust_fan_present': true,
      });
      expect(s.leftAuxFanSpeed, 40);
      expect(s.exhaustFanPresent, isTrue);
    });

    test('serwer < 1.2.5.2 nie wysyła pól → null, nie false', () {
      final s = PrinterStatus.fromJson(const {'id': 1, 'model': 'P2S'});
      expect(s.leftAuxFanSpeed, isNull);
      // Musi zostać null: false znaczy "serwer sprawdził i nie ma".
      expect(s.exhaustFanPresent, isNull);
    });

    test('etykieta wyciągu tylko dla P2S/X2D, też po kodzie wewnętrznym', () {
      for (final model in ['P2S', 'p2s', 'X2D', 'N7', 'N6', 'X2 D']) {
        expect(PrinterStatus(id: 1, model: model).usesExhaustFanLabel, isTrue,
            reason: model);
      }
      for (final model in ['X1C', 'P1S', 'H2D', 'A1 mini', null]) {
        expect(PrinterStatus(id: 1, model: model).usesExhaustFanLabel, isFalse,
            reason: '$model');
      }
    });

    test('P2S bez zestawu wyciągu — kafelek ukryty', () {
      const s = PrinterStatus(
        id: 1,
        model: 'P2S',
        bigFan2Speed: 0,
        exhaustFanPresent: false,
      );
      expect(s.chamberFanAvailable, isFalse);
    });

    test('P2S z zestawem — kafelek widoczny', () {
      const s = PrinterStatus(
        id: 1,
        model: 'P2S',
        bigFan2Speed: 60,
        exhaustFanPresent: true,
      );
      expect(s.chamberFanAvailable, isTrue);
    });

    test('P2S na starym serwerze — zachowanie sprzed zmiany (pokazujemy)', () {
      const s = PrinterStatus(id: 1, model: 'P2S', bigFan2Speed: 0);
      expect(s.chamberFanAvailable, isTrue);
    });

    test('X1C z exhaust_fan_present=false dalej ma wentylator komory', () {
      // Regresja, o którą tu najłatwiej: X1C/P1S nie mają airductu, więc serwer
      // raportuje im `false` przy wentylatorze, który fizycznie jest.
      const s = PrinterStatus(
        id: 1,
        model: 'X1C',
        bigFan2Speed: 45,
        exhaustFanPresent: false,
      );
      expect(s.chamberFanAvailable, isTrue);
    });

    test('brak big_fan2_speed → brak kafelka niezależnie od modelu', () {
      const s = PrinterStatus(id: 1, model: 'X2D', exhaustFanPresent: true);
      expect(s.chamberFanAvailable, isFalse);
    });

    test('merge dziedziczy oba pola z poprzedniej ramki', () {
      const prev = PrinterStatus(
        id: 1,
        model: 'P2S',
        leftAuxFanSpeed: 30,
        exhaustFanPresent: true,
      );
      const poll = PrinterStatus(id: 1, bigFan1Speed: 50);
      final merged = poll.mergedWith(prev);
      expect(merged.leftAuxFanSpeed, 30);
      expect(merged.exhaustFanPresent, isTrue);
    });

    test('offline gasi prędkość, ale zachowuje informację o obecności', () {
      const prev = PrinterStatus(
        id: 1,
        model: 'P2S',
        leftAuxFanSpeed: 30,
        bigFan2Speed: 60,
        exhaustFanPresent: false,
      );
      const off = PrinterStatus(id: 1, connected: false);
      final merged = off.mergedWith(prev);
      expect(merged.leftAuxFanSpeed, isNull);
      // Zestaw nie znika po zaniku zasilania — inaczej po powrocie bazowy P2S
      // mignąłby kafelkiem komory, czekając na pierwszą ramkę airduct.
      expect(merged.exhaustFanPresent, isFalse);
    });
  });

  group('PrinterStatus.isCalibration', () {
    test('plik auto_cali_for_user_param liczy się jako kalibracja', () {
      const s = PrinterStatus(
        id: 1,
        state: 'RUNNING',
        gcodeFile: 'auto_cali_for_user_param.gcode',
      );
      expect(s.isCalibration, isTrue);
    });

    test('zwykły wydruk nie jest kalibracją', () {
      const s = PrinterStatus(id: 1, state: 'RUNNING', gcodeFile: 'benchy.gcode');
      expect(s.isCalibration, isFalse);
    });

    test('brak nazwy pliku → nie kalibracja', () {
      const s = PrinterStatus(id: 1, state: 'IDLE');
      expect(s.isCalibration, isFalse);
    });
  });

  group('nozzles', () {
    PrinterStatus withNozzles(List<Map<String, String>> nozzles,
            {Map<String, int>? extruderMap, Map<String, String>? inlets}) =>
        PrinterStatus.fromJson({
          'id': 1,
          'nozzles': nozzles,
          'ams_extruder_map': ?extruderMap,
          'ams_switch_inlet': ?inlets,
        });

    test('parses the fitted nozzles', () {
      final status = withNozzles([
        {'nozzle_type': 'hardened_steel', 'nozzle_diameter': '0.4'},
      ]);

      expect(status.nozzles, hasLength(1));
      expect(status.nozzles!.single.nozzleType, 'hardened_steel');
      expect(status.nozzleDiameterFor(0, 0), '0.4');
    });

    test('answers the diameter of the nozzle the AMS unit feeds', () {
      // Dual-head printers can carry two different sizes, and the slot
      // configuration has to name the one that will actually melt this spool.
      final status = withNozzles(
        [
          {'nozzle_diameter': '0.4'},
          {'nozzle_diameter': '0.8'},
        ],
        extruderMap: {'0': 1},
      );

      expect(status.nozzleDiameterFor(0, 0), '0.8');
      expect(status.nozzleDiameterFor(1, 0), isNull,
          reason: 'two sizes and no mapping for this unit — the caller guesses');
    });

    test('answers per side for the external holder', () {
      // Unit 255 is in no extruder map: the tray id is the whole answer, and
      // reading it as extruder 0 gave Ext-L the right-hand nozzle's size.
      final status = withNozzles([
        {'nozzle_diameter': '0.4'},
        {'nozzle_diameter': '0.8'},
      ]);

      expect(status.nozzleDiameterFor(255, 0), '0.8',
          reason: 'tray 0 is Ext-L, extruder 1');
      expect(status.nozzleDiameterFor(255, 1), '0.4');
    });

    test('a matched pair needs no side', () {
      // The stub second entry a single-nozzle printer reports, and the common
      // dual machine wearing two 0.4s, both answer without knowing the side.
      final single = withNozzles([
        {'nozzle_diameter': '0.4'},
        {'nozzle_diameter': ''},
      ]);
      final matched = withNozzles([
        {'nozzle_diameter': '0.4'},
        {'nozzle_diameter': '0.4'},
      ]);

      expect(single.nozzleDiameterFor(3, 0), '0.4');
      expect(matched.nozzleDiameterFor(255, 0), '0.4');
    });

    test('reads the side off the switch inlet when the map is empty', () {
      // An FTS machine reports 0xE for every AMS, so `ams_extruder_map` is
      // empty and the inlet binding is the only side there is.
      final status = withNozzles(
        [
          {'nozzle_diameter': '0.4'},
          {'nozzle_diameter': '0.8'},
        ],
        extruderMap: const {},
        inlets: {'0': 'A', '1': 'B'},
      );

      expect(status.nozzleDiameterFor(0, 0), '0.8', reason: 'inlet A → left');
      expect(status.nozzleDiameterFor(1, 0), '0.4', reason: 'inlet B → right');
      expect(status.nozzleDiameterFor(2, 0), isNull,
          reason: 'a unit on neither inlet stays unknown');
    });

    test('answers null when the printer reported no nozzles', () {
      // Guessing 0.4 here would hide the gap; the caller decides what to send.
      expect(const PrinterStatus(id: 1).nozzleDiameterFor(0, 0), isNull);
      expect(withNozzles(const []).nozzleDiameterFor(0, 0), isNull);
      expect(
          withNozzles([
            {'nozzle_diameter': ''},
            {'nozzle_diameter': ''},
          ]).nozzleDiameterFor(0, 0),
          isNull);
    });

    test('survives the printer going offline', () {
      // Which nozzle is fitted does not change while the printer is
      // unreachable, unlike the telemetry around it.
      final offline = const PrinterStatus(id: 1, connected: false)
          .mergedWith(withNozzles([
        {'nozzle_diameter': '0.6'},
      ]));

      expect(offline.nozzleDiameterFor(0, 0), '0.6');
    });
  });

  group('slot addressing', () {
    test('a single external holder feeds the only nozzle there is', () {
      // One holder means one nozzle, and that one is extruder 0 — the inverted
      // 254/255 pair only describes a dual-head machine.
      final single = PrinterStatus.fromJson(const {
        'id': 1,
        'vt_tray': [
          {'id': 254, 'tray_type': 'PLA'},
        ],
      });

      expect(single.extruderForExternal(254), 0);
      expect(single.extruderForExternal(255), isNull,
          reason: 'a spool this printer does not report');
    });

    test('an AMS-HT slot is found by tray_now', () {
      // An HT unit holds one tray and is numbered from 128, so `unit * 4 + slot`
      // put it at 512 and `tray_now: 128` matched nothing.
      final status = PrinterStatus.fromJson(const {
        'id': 1,
        'tray_now': 128,
        'ams': [
          {
            'id': 128,
            'tray': [
              {'id': 0, 'tray_type': 'PA-CF'},
            ],
          },
        ],
      });

      expect(status.activeTray?.trayType, 'PA-CF');
    });

    test('a tray without an id matches nothing rather than something else', () {
      // Reading a missing slot id as 0 made unit 1's phantom slot collide with
      // unit 0's fourth one.
      final status = PrinterStatus.fromJson(const {
        'id': 1,
        'tray_now': 3,
        'ams': [
          {
            'id': 0,
            'tray': [
              {'tray_type': 'PLA'},
            ],
          },
          {
            'id': 1,
            'tray': [
              {'tray_type': 'PETG'},
            ],
          },
        ],
      });

      expect(status.activeTray, isNull);
    });
  });

  group('ams_switch_inlet', () {
    PrinterStatus withInlets(Object? raw) =>
        PrinterStatus.fromJson({'id': 1, 'ams_switch_inlet': raw});

    test('parses the string-keyed inlet map', () {
      expect(withInlets({'0': 'A', '1': 'B'}).amsSwitchInlet, {0: 'A', 1: 'B'});
    });

    test('an older server that never sends it leaves it null', () {
      // The whole compatibility story: no field, no FTS assumptions, and
      // `ams_extruder_map` keeps answering exactly as it did before.
      final status = PrinterStatus.fromJson(const {
        'id': 1,
        'ams_extruder_map': {'0': 1},
      });

      expect(status.amsSwitchInlet, isNull);
      expect(status.extruderForSlot(0, 0), 1);
      expect(status.extruderForSlot(1, 0), isNull);
    });

    test('a non-map value does not take the parser down', () {
      expect(withInlets('nonsense').amsSwitchInlet, isNull);
      expect(withInlets({'0': 7, 'x': 'A'}).amsSwitchInlet, isEmpty);
    });

    test('a frame without the field keeps the last known binding', () {
      // Same rule as the rest of the merge: a WebSocket push that omits it
      // must not unbind the AMS the REST snapshot had bound.
      final previous = withInlets({'0': 'A'});
      final merged = const PrinterStatus(id: 1, progress: 12).mergedWith(previous);

      expect(merged.amsSwitchInlet, {0: 'A'});
    });

    test('the binding survives the printer going offline', () {
      // Plumbing does not change while the machine is unreachable — and the
      // AMS inventory it belongs to is kept for the same reason.
      final offline = const PrinterStatus(id: 1, connected: false)
          .mergedWith(withInlets({'0': 'B'}));

      expect(offline.amsSwitchInlet, {0: 'B'});
    });

    test('an FTS machine still counts as dual-extruder', () {
      // Its AMS units drop out of `ams_extruder_map`, which used to be the
      // signal — losing it hid the extruder badges and the side labels.
      expect(withInlets({'0': 'A'}).isDualExtruder, isTrue);
      expect(withInlets(const {}).isDualExtruder, isFalse);
    });

    test('an emptied binding wins over the last known one', () {
      // The server sends `{}` once the accessory is unplugged, and an empty
      // map is a value, not a gap — the stale binding has to go.
      final merged = withInlets(const {}).mergedWith(withInlets({'0': 'A'}));

      expect(merged.amsSwitchInlet, isEmpty);
    });
  });

  group('tray configuration fields', () {
    test('parses the filament id and calibration index of a slot', () {
      final frame =
          readFixture('ws_printer_status.json') as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(frame['data'] as Map);
      data['id'] = frame['printer_id'];
      final status = PrinterStatus.fromJson(data);

      // The name alone cannot identify which preset a slot holds — two presets
      // share one, and a user preset resolves to no name at all.
      expect(status.ams!.first.trays![3].trayInfoIdx, 'GFA00');
      expect(status.ams!.first.trays![3].caliIdx, -1);
      expect(status.vtTray!.first.trayInfoIdx, 'GFU01');
    });

    test('a slot whose filament id changed is not equal to the old one', () {
      // Equality drives whether a fresh poll is published at all — a slot
      // reconfigured to another preset has to get through.
      expect(const AmsTray(id: 0, trayType: 'PLA', trayInfoIdx: 'GFL99'),
          isNot(const AmsTray(id: 0, trayType: 'PLA', trayInfoIdx: 'GFL05')));
    });
  });

  group('Filament Track Switch', () {
    test('parses the switch and which hotend holds which slot', () {
      final status = PrinterStatus.fromJson({
        'id': 1,
        'fila_switch': {'installed': true, 'ready': true},
        'extruder_slots': {
          '0': {'ams_id': 1, 'slot_id': 2, 'has_filament': true},
          '1': {'ams_id': null, 'slot_id': null, 'has_filament': false},
        },
      });

      expect(status.filaSwitch!.installed, isTrue);
      expect(status.filaSwitch!.ready, isTrue);
      expect(status.extruderSlots![0]!.holds(amsId: 1, slotId: 2), isTrue);
      expect(status.extruderSlots![0]!.holds(amsId: 1, slotId: 3), isFalse);
      expect(status.extruderSlots![1]!.holds(amsId: 1, slotId: 2), isFalse,
          reason: 'a hotend fed from nothing holds no slot');
    });

    test('reads a server that never mentions the switch as not having one', () {
      // Every server older than the one that added the field, and every printer
      // without the accessory, answer the same way — and the same way matters,
      // because it is what keeps the load command shaped as it always was.
      final status = PrinterStatus.fromJson({'id': 1});

      expect(status.filaSwitch, isNull);
      expect(status.extruderSlots, isNull);
    });

    test('a switch reported without `ready` is not ready', () {
      // False blocks the load with an explanation. True would send a command
      // the firmware drops without a word, which is the bug being fixed.
      final status = PrinterStatus.fromJson({
        'id': 1,
        'fila_switch': {'installed': true},
      });

      expect(status.filaSwitch!.installed, isTrue);
      expect(status.filaSwitch!.ready, isFalse);
    });

    test('a frame that omits the switch keeps the one already known', () {
      // The two lanes carry disjoint subsets, so absence is silence, not news —
      // the same rule the rest of the status follows.
      final known = PrinterStatus.fromJson({
        'id': 1,
        'fila_switch': {'installed': true, 'ready': true},
        'extruder_slots': {
          '0': {'ams_id': 0, 'slot_id': 1},
        },
      });

      final merged = const PrinterStatus(id: 1, progress: 12).mergedWith(known);

      expect(merged.filaSwitch!.installed, isTrue);
      expect(merged.extruderSlots![0]!.holds(amsId: 0, slotId: 1), isTrue);
    });

    test('the fitted switch survives the printer going offline', () {
      // Hardware, like the nozzles: unplugging the printer does not remove it,
      // and the slot sheet still has to ask the question on reconnect.
      final offline = const PrinterStatus(id: 1, connected: false).mergedWith(
        PrinterStatus.fromJson({
          'id': 1,
          'fila_switch': {'installed': true, 'ready': true},
        }),
      );

      expect(offline.filaSwitch!.installed, isTrue);
    });

    test('a switch that changed makes the status unequal', () {
      // Equality decides whether a fresh poll is published at all: a switch that
      // has just become ready has to reach the sheet that is blocking on it.
      PrinterStatus withReady(bool ready) => PrinterStatus.fromJson({
            'id': 1,
            'fila_switch': {'installed': true, 'ready': ready},
          });

      expect(withReady(true), isNot(withReady(false)));
      expect(withReady(true), withReady(true));
    });
  });

  group('Printer.fromJson', () {
    test('parsuje listę drukarek, ignorując nieznane pola', () {
      final raw = readFixture('printers_list.json') as List<dynamic>;
      final printers = raw
          .map((e) => Printer.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(printers, hasLength(2));
      expect(printers[0].name, 'X1C Warsztat');
      expect(printers[0].ipAddress, '192.168.1.50');
      expect(printers[1].location, isNull);
      expect(printers[1].isActive, isFalse);
    });
  });
}
