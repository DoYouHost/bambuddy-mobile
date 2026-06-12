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
