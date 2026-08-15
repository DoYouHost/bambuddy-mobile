import 'dart:convert';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('parseWsMessage', () {
    test('parsuje PRAWDZIWĄ ramkę printer_status z żywego serwera', () {
      final msg = parseWsMessage(readFixtureString('ws_printer_status.json'));

      expect(msg, isA<WsPrinterStatus>());
      final status = (msg as WsPrinterStatus).status;

      // id wstrzyknięty z printer_id (data go nie zawiera).
      expect(status.id, 1);
      expect(status.name, 'X2D-3DP');
      expect(status.state, 'RUNNING');
      expect(status.connected, isTrue);
      expect(status.totalLayers, 824);

      // Pola sterowania przychodzą tym samym kanałem co przez REST.
      expect(status.coolingFanSpeed, 0);
      expect(status.bigFan1Speed, 40);
      expect(status.bigFan2Speed, 67);
      expect(status.heatbreakFanSpeed, 93);
      expect(status.speedLevel, 2);
      expect(status.speedPercent, 100);
      expect(status.chamberLight, isTrue);
      // Ta drukarka (P1S/X2D) nie raportuje airduct_mode.
      expect(status.airductMode, isNull);

      // RUNNING z progress 0 → faza przygotowania (etap z stg_cur_name).
      expect(status.isPreparing, isTrue);
      expect(status.stgCurName, 'Waiting for heatbed temperature');
    });

    test('temperatury: tylko wpisy liczbowe, boole *_heating pominięte', () {
      final msg = parseWsMessage(readFixtureString('ws_printer_status.json'))
          as WsPrinterStatus;
      final temps = msg.status.temperatures!;

      expect(temps['nozzle'], 140.0);
      expect(temps['bed'], 70.0);
      expect(temps['chamber'], 33.0);
      expect(temps['chamber_target'], 0.0);
      // Flagi grzania to boole w tej samej mapie — parser je odrzuca.
      expect(temps.containsKey('nozzle_heating'), isFalse);
      expect(temps.containsKey('bed_heating'), isFalse);
      expect(temps.values, everyElement(isA<double>()));
    });

    test('pong → WsPong', () {
      expect(parseWsMessage('{"type":"pong"}'), isA<WsPong>());
    });

    test('plate_not_empty → WsPlateNotEmpty z id/nazwą/wiadomością', () {
      final raw = jsonEncode({
        'type': 'plate_not_empty',
        'printer_id': 3,
        'printer_name': 'X1C',
        'message': 'Objects detected on build plate! Print paused.',
      });
      final msg = parseWsMessage(raw);
      expect(msg, isA<WsPlateNotEmpty>());
      final plate = msg! as WsPlateNotEmpty;
      expect(plate.printerId, 3);
      expect(plate.printerName, 'X1C');
      expect(plate.message, contains('Print paused'));
    });

    test('plate_not_empty bez printer_id → WsUnknown', () {
      final msg = parseWsMessage('{"type":"plate_not_empty","message":"x"}');
      expect(msg, isA<WsUnknown>());
    });

    test('print_complete → WsPrintEvent completed z printer_id', () {
      final msg = parseWsMessage('{"type":"print_complete","printer_id":5}');
      expect(msg, isA<WsPrintEvent>());
      final ev = msg! as WsPrintEvent;
      expect(ev.printerId, 5);
      expect(ev.completed, isTrue);
    });

    test('print_start → WsPrintEvent nie-completed', () {
      final msg = parseWsMessage('{"type":"print_start","printer_id":2}');
      expect(msg, isA<WsPrintEvent>());
      final ev = msg! as WsPrintEvent;
      expect(ev.printerId, 2);
      expect(ev.completed, isFalse);
    });

    test('archive_updated z photo_added → WsArchiveUpdated', () {
      final raw = jsonEncode({
        'type': 'archive_updated',
        'data': {'id': 82, 'photo_added': 'finish_20260815_120000_ab12.jpg'},
      });
      final msg = parseWsMessage(raw);
      expect(msg, isA<WsArchiveUpdated>());
      final archive = msg! as WsArchiveUpdated;
      expect(archive.archiveId, 82);
      expect(archive.photoAdded, 'finish_20260815_120000_ab12.jpg');
    });

    test('archive_updated bez zdjęcia (np. timelapse) → photoAdded null', () {
      final raw = jsonEncode({
        'type': 'archive_updated',
        'data': {'id': 82, 'timelapse_attached': true},
      });
      final msg = parseWsMessage(raw);
      expect(msg, isA<WsArchiveUpdated>());
      expect((msg! as WsArchiveUpdated).photoAdded, isNull);
    });

    test('archive_updated bez id w data → WsUnknown', () {
      final msg = parseWsMessage('{"type":"archive_updated","data":{"x":1}}');
      expect(msg, isA<WsUnknown>());
    });

    test('print_complete bez printer_id → WsUnknown', () {
      final msg = parseWsMessage('{"type":"print_complete"}');
      expect(msg, isA<WsUnknown>());
    });

    test('nieznany typ zachowuje się jako WsUnknown z type', () {
      final msg = parseWsMessage('{"type":"spoolbuddy_update","x":1}');
      expect(msg, isA<WsUnknown>());
      expect((msg! as WsUnknown).type, 'spoolbuddy_update');
    });

    test('printer_status bez data → WsUnknown (nie crash)', () {
      final msg = parseWsMessage('{"type":"printer_status","printer_id":1}');
      expect(msg, isA<WsUnknown>());
    });

    test('printer_status bez printer_id → WsUnknown', () {
      final msg = parseWsMessage('{"type":"printer_status","data":{}}');
      expect(msg, isA<WsUnknown>());
    });

    test('printer_id jako string jest tolerowany', () {
      final raw = jsonEncode({
        'type': 'printer_status',
        'printer_id': '7',
        'data': {'state': 'IDLE'},
      });
      final msg = parseWsMessage(raw) as WsPrinterStatus;
      expect(msg.status.id, 7);
      expect(msg.status.state, 'IDLE');
    });

    test('nie-JSON → null', () {
      expect(parseWsMessage('to nie jest json'), isNull);
    });

    test('JSON nie-obiekt (tablica/liczba) → null', () {
      expect(parseWsMessage('[1,2,3]'), isNull);
      expect(parseWsMessage('42'), isNull);
    });

    test('ramka bez type → WsUnknown(null)', () {
      final msg = parseWsMessage('{"foo":"bar"}');
      expect(msg, isA<WsUnknown>());
      expect((msg! as WsUnknown).type, isNull);
    });
  });
}
