import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/features/queue/queue_form_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('three segments, Auto first, as every print form shows them', () {
    expect(
      [
        for (final s in calibrationSegments(pl, triState: true))
          (s.value, s.label),
      ],
      [
        (CalibrationOption.auto, pl.commonAuto),
        (CalibrationOption.on, pl.commonOn),
        (CalibrationOption.off, pl.commonOff),
      ],
    );
  });

  test('a server that cannot keep Auto gets no Auto segment', () {
    expect(
      [for (final s in calibrationSegments(pl, triState: false)) s.value],
      [CalibrationOption.on, CalibrationOption.off],
    );
  });

  test('as a switch, Auto reads as on', () {
    expect(calibrationLabel(pl, CalibrationOption.auto, false), pl.commonOn);
    expect(calibrationLabel(pl, CalibrationOption.auto, true), pl.commonAuto);
  });
}
