import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domyślne: wszystko włączone poza timelapse', () {
    const o = PrintOptions.initial;
    expect([o.vibrationCali, o.layerInspect], everyElement(isTrue));
    expect(
      [o.bedLevelling, o.flowCali, o.nozzleOffsetCali],
      everyElement(CalibrationOption.on),
      reason: 'on, nie auto — starszy serwer nie ma gdzie zapisać auto',
    );
    expect(o.timelapse, isFalse, reason: 'nagranie tylko na żądanie');
    expect(
      o.gcodeInjection,
      isFalse,
      reason: 'wstrzykiwanie G-code tylko na wyraźne życzenie',
    );
  });

  test('encode → decode wraca tym samym', () {
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
    'zapis z poprzedniej wersji: booleany na kalibracjach nadal się czytają',
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

  test('brak zapisu → domyślne', () {
    expect(PrintOptions.decode(null), PrintOptions.initial);
    expect(PrintOptions.decode(''), PrintOptions.initial);
  });

  test('uszkodzony zapis → domyślne, nie wyjątek', () {
    expect(PrintOptions.decode('{nie-json'), PrintOptions.initial);
    expect(PrintOptions.decode('[1,2,3]'), PrintOptions.initial);
  });

  test('niepełny zapis: brakujące pola biorą wartość domyślną', () {
    // An older build wrote fewer keys — the user loses the memory of one
    // toggle, not the whole print screen.
    final o = PrintOptions.decode('{"timelapse":true,"flow_cali":"tak"}');
    expect(o.timelapse, isTrue);
    expect(
      o.flowCali,
      PrintOptions.initial.flowCali,
      reason: 'zła wartość typu = brak wartości',
    );
    expect(o.bedLevelling, PrintOptions.initial.bedLevelling);
    expect(
      o.gcodeInjection,
      isFalse,
      reason: 'zapis sprzed wstrzykiwania G-code = wyłączone',
    );
  });
}
