import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domyślne: wszystko włączone poza timelapse', () {
    const o = PrintOptions.initial;
    expect(
      [o.bedLevelling, o.flowCali, o.vibrationCali, o.layerInspect, o.nozzleOffsetCali],
      everyElement(isTrue),
    );
    expect(o.timelapse, isFalse, reason: 'nagranie tylko na żądanie');
  });

  test('encode → decode wraca tym samym', () {
    const o = PrintOptions(
      bedLevelling: false,
      flowCali: true,
      vibrationCali: false,
      layerInspect: true,
      timelapse: true,
      nozzleOffsetCali: false,
    );
    expect(PrintOptions.decode(o.encode()), o);
  });

  test('brak zapisu → domyślne', () {
    expect(PrintOptions.decode(null), PrintOptions.initial);
    expect(PrintOptions.decode(''), PrintOptions.initial);
  });

  test('uszkodzony zapis → domyślne, nie wyjątek', () {
    expect(PrintOptions.decode('{nie-json'), PrintOptions.initial);
    expect(PrintOptions.decode('[1,2,3]'), PrintOptions.initial);
  });

  test('niepełny zapis: brakujące pola biorą wartość domyślną', () {
    // Starszy build zapisał mniej kluczy — user traci pamięć jednego
    // przełącznika, nie cały ekran druku.
    final o = PrintOptions.decode('{"timelapse":true,"flow_cali":"tak"}');
    expect(o.timelapse, isTrue);
    expect(o.flowCali, PrintOptions.initial.flowCali,
        reason: 'zła wartość typu = brak wartości');
    expect(o.bedLevelling, PrintOptions.initial.bedLevelling);
  });
}
