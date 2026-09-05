import 'dart:convert';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('parseWsMessage', () {
    test('parses a REAL printer_status frame off a live server', () {
      final msg = parseWsMessage(readFixtureString('ws_printer_status.json'));

      expect(msg, isA<WsPrinterStatus>());
      final status = (msg as WsPrinterStatus).status;

      // The id is injected from printer_id — `data` does not carry it.
      expect(status.id, 1);
      expect(status.name, 'X2D-3DP');
      expect(status.state, 'RUNNING');
      expect(status.connected, isTrue);
      expect(status.totalLayers, 824);

      // The control fields arrive on this channel exactly as they do over REST.
      expect(status.coolingFanSpeed, 0);
      expect(status.bigFan1Speed, 40);
      expect(status.bigFan2Speed, 67);
      expect(status.heatbreakFanSpeed, 93);
      expect(status.speedLevel, 2);
      expect(status.speedPercent, 100);
      expect(status.chamberLight, isTrue);
      // This printer (P1S/X2D) does not report airduct_mode.
      expect(status.airductMode, isNull);

      // RUNNING at progress 0 is the preparation phase, named by stg_cur_name.
      expect(status.isPreparing, isTrue);
      expect(status.stgCurName, 'Waiting for heatbed temperature');
    });

    test('temperatures: only the numeric entries, the *_heating bools dropped', () {
      final msg = parseWsMessage(readFixtureString('ws_printer_status.json'))
          as WsPrinterStatus;
      final temps = msg.status.temperatures!;

      expect(temps['nozzle'], 140.0);
      expect(temps['bed'], 70.0);
      expect(temps['chamber'], 33.0);
      expect(temps['chamber_target'], 0.0);
      // The heating flags are bools in the same map, and the parser rejects them.
      expect(temps.containsKey('nozzle_heating'), isFalse);
      expect(temps.containsKey('bed_heating'), isFalse);
      expect(temps.values, everyElement(isA<double>()));
    });

    test('pong → WsPong', () {
      expect(parseWsMessage('{"type":"pong"}'), isA<WsPong>());
    });

    test('plate_not_empty carries the id, the name and the message', () {
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

    test('plate_not_empty without a printer_id is WsUnknown', () {
      final msg = parseWsMessage('{"type":"plate_not_empty","message":"x"}');
      expect(msg, isA<WsUnknown>());
    });

    test('print_complete is a completed WsPrintEvent with the printer_id', () {
      final msg = parseWsMessage('{"type":"print_complete","printer_id":5}');
      expect(msg, isA<WsPrintEvent>());
      final ev = msg! as WsPrintEvent;
      expect(ev.printerId, 5);
      expect(ev.completed, isTrue);
    });

    test('print_start is a WsPrintEvent that is not completed', () {
      final msg = parseWsMessage('{"type":"print_start","printer_id":2}');
      expect(msg, isA<WsPrintEvent>());
      final ev = msg! as WsPrintEvent;
      expect(ev.printerId, 2);
      expect(ev.completed, isFalse);
    });

    test('archive_updated with photo_added is a WsArchiveUpdated', () {
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

    test('archive_updated with no photo — a timelapse — leaves photoAdded null', () {
      final raw = jsonEncode({
        'type': 'archive_updated',
        'data': {'id': 82, 'timelapse_attached': true},
      });
      final msg = parseWsMessage(raw);
      expect(msg, isA<WsArchiveUpdated>());
      expect((msg! as WsArchiveUpdated).photoAdded, isNull);
    });

    test('archive_updated with no id inside data is WsUnknown', () {
      final msg = parseWsMessage('{"type":"archive_updated","data":{"x":1}}');
      expect(msg, isA<WsUnknown>());
    });

    test('print_complete without a printer_id is WsUnknown', () {
      final msg = parseWsMessage('{"type":"print_complete"}');
      expect(msg, isA<WsUnknown>());
    });

    test('an unknown type keeps its name in WsUnknown', () {
      final msg = parseWsMessage('{"type":"spoolbuddy_update","x":1}');
      expect(msg, isA<WsUnknown>());
      expect((msg! as WsUnknown).type, 'spoolbuddy_update');
    });

    test('printer_status with no data is WsUnknown, not a crash', () {
      final msg = parseWsMessage('{"type":"printer_status","printer_id":1}');
      expect(msg, isA<WsUnknown>());
    });

    test('printer_status without a printer_id is WsUnknown', () {
      final msg = parseWsMessage('{"type":"printer_status","data":{}}');
      expect(msg, isA<WsUnknown>());
    });

    test('a printer_id sent as a string is tolerated', () {
      final raw = jsonEncode({
        'type': 'printer_status',
        'printer_id': '7',
        'data': {'state': 'IDLE'},
      });
      final msg = parseWsMessage(raw) as WsPrinterStatus;
      expect(msg.status.id, 7);
      expect(msg.status.state, 'IDLE');
    });

    test('text that is not JSON yields null', () {
      expect(parseWsMessage('to nie jest json'), isNull);
    });

    test('JSON that is not an object — an array, a number — yields null', () {
      expect(parseWsMessage('[1,2,3]'), isNull);
      expect(parseWsMessage('42'), isNull);
    });

    test('pipeline_run_updated carries the whole run under `run`', () {
      // A third shape: the printer frames put the id at the top level and
      // archive_updated wraps its payload in `data`.
      final msg = parseWsMessage(jsonEncode({
        'type': 'pipeline_run_updated',
        'run': {
          'id': 12,
          'pipeline_id': 3,
          'pipeline_name': 'Gridfinity PETG',
          'copies': 4,
          'copies_completed': 2,
          'status': 'in_progress',
          'eligibility_overridden': false,
          'created_at': '2026-08-10T09:00:00',
          'jobs': [],
        },
      }));

      expect(msg, isA<WsPipelineRunUpdated>());
      expect((msg! as WsPipelineRunUpdated).run['id'], 12);
      expect((msg as WsPipelineRunUpdated).run['status'], 'in_progress');
    });

    test('pipeline_run_updated with no run, or no id in it, is WsUnknown', () {
      // The dashboard replaces a row by id, so a frame without one names
      // nothing to replace and must not reach the feature at all.
      for (final frame in [
        {'type': 'pipeline_run_updated'},
        {'type': 'pipeline_run_updated', 'run': 'nonsense'},
        {'type': 'pipeline_run_updated', 'run': <String, dynamic>{}},
        {
          'type': 'pipeline_run_updated',
          'run': {'status': 'completed'},
        },
      ]) {
        expect(parseWsMessage(jsonEncode(frame)), isA<WsUnknown>(),
            reason: 'frame: $frame');
      }
    });

    test('a frame with no type at all is WsUnknown(null)', () {
      final msg = parseWsMessage('{"foo":"bar"}');
      expect(msg, isA<WsUnknown>());
      expect((msg! as WsUnknown).type, isNull);
    });
  });
}
