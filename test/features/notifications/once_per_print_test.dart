import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/features/notifications/print_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// The latch that keeps a per-print event from repeating once a second.
void main() {
  group('OncePerPrint', () {
    test('runs its body the first time and never again', () {
      final once = OncePerPrint();
      var runs = 0;

      once.claim(() => runs++);
      once.claim(() => runs++);
      once.claim(() => runs++);

      expect(runs, 1);
    });

    test('says which call was the one that fired', () {
      final once = OncePerPrint();

      expect(once.claim(), isTrue);
      expect(once.claim(), isFalse);
    });

    test('a body is optional, for a latch that only gates an alert', () {
      final once = OncePerPrint();

      expect(once.claim(), isTrue);
      expect(once.fired, isTrue);
    });

    test('reset opens it again, which is what a new print does', () {
      final once = OncePerPrint()..claim();

      once.reset();

      expect(once.fired, isFalse);
      expect(once.claim(), isTrue);
    });
  });

  group('PrinterStatus frame predicates', () {
    PrinterStatus frame({int? layer, int? stage}) =>
        PrinterStatus(id: 1, layerNum: layer, stgCur: stage);

    test('a layer with no named stage is a job being laid down', () {
      expect(frame(layer: 3, stage: 0).jobUnderway, isTrue);
    });

    test('a named stage is the printer busy with itself, not printing', () {
      // The firmware ticks layer_num through bed levelling and nozzle cleaning,
      // so the counter alone is not evidence the print is running.
      expect(frame(layer: 3, stage: 2).jobUnderway, isFalse);
    });

    test('a frame with no counter is taken as underway', () {
      // A printer mid-job that omitted the field must not read as idle.
      expect(frame(stage: 0).jobUnderway, isTrue);
    });

    test('layer 2 is the first layer done, layer 1 is it being printed', () {
      expect(frame(layer: 1).firstLayerInWindow, isFalse);
      expect(frame(layer: 2).firstLayerInWindow, isTrue);
    });

    test('past the window the counter belongs to another print', () {
      expect(frame(layer: 10).firstLayerInWindow, isTrue);
      expect(frame(layer: 11).firstLayerInWindow, isFalse);
      expect(frame(layer: 400).firstLayerInWindow, isFalse);
    });

    test('no counter is not a first layer', () {
      expect(frame().firstLayerInWindow, isFalse);
    });

    // The baseline reading, for a monitor that wakes up mid-print: spent, not
    // due. Each case of the pair separately, because the two lanes drifted
    // apart once already.
    test('the baseline reading has the same floor as the window', () {
      expect(frame(layer: 1).firstLayerPassed, isFalse);
      expect(frame(layer: 2).firstLayerPassed, isTrue);
      expect(frame().firstLayerPassed, isFalse);
    });

    test('the baseline reading has no ceiling — the window is the ceiling', () {
      expect(frame(layer: 11).firstLayerPassed, isTrue);
      expect(frame(layer: 400).firstLayerPassed, isTrue);
      expect(frame(layer: 400).firstLayerInWindow, isFalse);
    });

    test('the window says nothing about the stage', () {
      // Deliberately: whether a printer in a stage of its own laid that layer
      // down is a second question, and its caller also has to record the frame
      // it turned down.
      expect(frame(layer: 2, stage: 2).firstLayerInWindow, isTrue);
    });
  });
}
