import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults: everything on except timelapse', () {
    const o = PrintOptions.initial;
    expect([o.vibrationCali, o.layerInspect], everyElement(isTrue));
    expect(
      [o.bedLevelling, o.flowCali, o.nozzleOffsetCali],
      everyElement(CalibrationOption.on),
      reason: 'on, not auto — an older server has nowhere to store auto',
    );
    expect(o.timelapse, isFalse, reason: 'recording only on request');
    expect(
      o.gcodeInjection,
      isFalse,
      reason: 'G-code injection only on explicit request',
    );
  });

  test('encode → decode returns the same thing', () {
    const o = PrintOptions(
      bedLevelling: CalibrationOption.off,
      flowCali: CalibrationOption.auto,
      vibrationCali: false,
      layerInspect: true,
      timelapse: true,
      nozzleOffsetCali: CalibrationOption.on,
      gcodeInjection: true,
    );
    expect(PrintOptions.decode(o.encode()), o);
  });

  test(
    'a save from a previous version: booleans on calibrations still read',
    () {
      // Blob written before the tri-state migration. The user should get their
      // toggles back rather than fall back to the initial values.
      final o = PrintOptions.decode(
        '{"bed_levelling":false,"flow_cali":true,'
        '"vibration_cali":true,"layer_inspect":false,'
        '"timelapse":false,"nozzle_offset_cali":true}',
      );
      expect(o.bedLevelling, CalibrationOption.off);
      expect(o.flowCali, CalibrationOption.on);
      expect(o.nozzleOffsetCali, CalibrationOption.on);
      expect(o.layerInspect, isFalse);
    },
  );

  test('no saved value → defaults', () {
    expect(PrintOptions.decode(null), PrintOptions.initial);
    expect(PrintOptions.decode(''), PrintOptions.initial);
  });

  test('a corrupted save → defaults, not an exception', () {
    expect(PrintOptions.decode('{not-json'), PrintOptions.initial);
    expect(PrintOptions.decode('[1,2,3]'), PrintOptions.initial);
  });

  test('an incomplete save: missing fields take the default value', () {
    // An older build wrote fewer keys — the user loses the memory of one
    // toggle, not the whole print screen.
    final o = PrintOptions.decode('{"timelapse":true,"flow_cali":"yes"}');
    expect(o.timelapse, isTrue);
    expect(
      o.flowCali,
      PrintOptions.initial.flowCali,
      reason: 'wrong value type = no value',
    );
    expect(o.bedLevelling, PrintOptions.initial.bedLevelling);
    expect(
      o.gcodeInjection,
      isFalse,
      reason: 'a save from before G-code injection = disabled',
    );
  });
}
