import 'package:bambuddy_mobile/core/models/next_pause.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/pause_marker.dart';
import 'package:flutter_test/flutter_test.dart';

PrinterStatus _status({
  NextPause? pause,
  double? progress = 20,
  int? remaining = 80,
  int? layers = 200,
}) => PrinterStatus(
  id: 1,
  connected: true,
  state: 'RUNNING',
  progress: progress,
  remainingTime: remaining,
  totalLayers: layers,
  nextPause: pause,
);

void main() {
  group('where the tick sits on the bar', () {
    test('on the bar\'s own scale when the minutes are known', () {
      // 20% done with 80 minutes left: the whole print is 100 minutes, and a
      // pause 40 minutes away is at 20% + 40%.
      final at = pauseTickFraction(
        _status(pause: const NextPause(layer: 120, minutes: 40)),
      );
      expect(at, closeTo(0.6, 1e-9));
    });

    test('a pause that is here sits on the fill\'s edge', () {
      final at = pauseTickFraction(
        _status(pause: const NextPause(layer: 41, minutes: 0)),
      );
      expect(at, closeTo(0.2, 1e-9));
    });

    test('never past the end, however many minutes it claims', () {
      final at = pauseTickFraction(
        _status(pause: const NextPause(layer: 150, minutes: 500)),
      );
      expect(at, 1.0);
    });

    test('falls back to the layer\'s share when the minutes are unknown', () {
      final at = pauseTickFraction(
        _status(pause: const NextPause(layer: 50), remaining: 0),
      );
      expect(at, 0.25);
    });

    test('falls back to the layer when the printer reports no time left', () {
      final at = pauseTickFraction(
        _status(
          pause: const NextPause(layer: 100, minutes: 10),
          remaining: null,
        ),
      );
      expect(at, 0.5);
    });

    test('has no place for it without minutes and without a layer count', () {
      expect(
        pauseTickFraction(
          _status(pause: const NextPause(layer: 50), layers: null),
        ),
        isNull,
      );
      expect(
        pauseTickFraction(
          _status(pause: const NextPause(layer: 500), layers: 200),
        ),
        isNull,
        reason: 'a layer beyond the print is not on the bar',
      );
    });

    test('the layers\' share is never drawn behind the fill', () {
      // 60% done, yet only layer 45 of 100: the tick is on the fill's edge,
      // not inside the part already printed.
      final at = pauseTickFraction(
        _status(
          pause: const NextPause(layer: 45),
          progress: 60,
          remaining: 0,
          layers: 100,
        ),
      );
      expect(at, 0.6);
    });

    test('a finished bar has no tick, whatever the layers say', () {
      expect(
        pauseTickFraction(
          _status(
            pause: const NextPause(layer: 50),
            progress: 100,
            remaining: 0,
            layers: 100,
          ),
        ),
        isNull,
      );
    });

    test('no pause, no tick', () {
      expect(pauseTickFraction(_status()), isNull);
    });

    test('a finished bar has nowhere to put minutes', () {
      expect(
        pauseTickFraction(
          _status(
            pause: const NextPause(layer: 10, minutes: 5),
            progress: 100,
            layers: null,
          ),
        ),
        isNull,
      );
    });
  });
}
