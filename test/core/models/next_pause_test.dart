import 'package:bambuddy_mobile/core/models/next_pause.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextPauseFromJson', () {
    test('reads the layer and the minutes', () {
      expect(
        nextPauseFromJson({'layer': 112, 'minutes': 20}),
        const NextPause(layer: 112, minutes: 20),
      );
    });

    test('minutes may be null: the layer is known, the time is not', () {
      expect(
        nextPauseFromJson({'layer': 112, 'minutes': null}),
        const NextPause(layer: 112),
      );
      expect(nextPauseFromJson({'layer': 112}), const NextPause(layer: 112));
    });

    test('zero minutes is a pause that is here, not a missing one', () {
      expect(nextPauseFromJson({'layer': 3, 'minutes': 0})?.minutes, 0);
    });

    test('no pause: null, the key missing or an object without a layer', () {
      expect(nextPauseFromJson(null), isNull);
      expect(nextPauseFromJson('nonsense'), isNull);
      expect(nextPauseFromJson({'minutes': 5}), isNull);
      expect(nextPauseFromJson({'layer': 'x'}), isNull);
    });

    test('numbers spelled as strings still count', () {
      expect(
        nextPauseFromJson({'layer': '7', 'minutes': '9'}),
        const NextPause(layer: 7, minutes: 9),
      );
    });
  });

  group('on a status', () {
    Map<String, dynamic> frame({Object? pause = _absent, String? name}) => {
      'id': 1,
      'connected': true,
      'state': 'RUNNING',
      'progress': 20,
      'remaining_time': 60,
      'layer_num': 10,
      'total_layers': 100,
      'name': ?name,
      if (pause != _absent) 'next_pause': pause,
    };

    test('is read from next_pause', () {
      final s = PrinterStatus.fromJson(
        frame(pause: {'layer': 50, 'minutes': 30}),
      );
      expect(s.nextPause, const NextPause(layer: 50, minutes: 30));
    });

    test('a frame with no pause ahead takes the last one away', () {
      final before = PrinterStatus.fromJson(
        frame(pause: {'layer': 50, 'minutes': 30}),
      );
      final after = PrinterStatus.fromJson(frame(pause: null));

      expect(after.mergedWith(before).nextPause, isNull);
    });

    test('a later frame replaces the minutes', () {
      final before = PrinterStatus.fromJson(
        frame(pause: {'layer': 50, 'minutes': 30}),
      );
      final after = PrinterStatus.fromJson(
        frame(pause: {'layer': 50, 'minutes': 29}),
      );

      expect(after.mergedWith(before).nextPause?.minutes, 29);
    });

    test('a printer that goes offline has no pause ahead', () {
      final before = PrinterStatus.fromJson(
        frame(pause: {'layer': 50, 'minutes': 30}),
      );
      final gone = PrinterStatus.fromJson({'id': 1, 'connected': false});

      expect(gone.mergedWith(before).nextPause, isNull);
    });

    test('statuses that differ only in the minutes are not equal', () {
      PrinterStatus at(int minutes) => PrinterStatus.fromJson(
        frame(pause: {'layer': 50, 'minutes': minutes}),
      );
      expect(at(30), at(30));
      expect(at(30), isNot(at(29)));
    });
  });
}

const _absent = Object();
