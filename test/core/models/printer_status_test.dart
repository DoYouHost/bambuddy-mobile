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
