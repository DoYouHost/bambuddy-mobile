import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('odczyt', () {
    test('boolean ze starszego serwera', () {
      expect(calibrationFromJson(true), CalibrationOption.on);
      expect(calibrationFromJson(false), CalibrationOption.off);
    });

    test('string z bambuddy 1.2.5+', () {
      expect(calibrationFromJson('on'), CalibrationOption.on);
      expect(calibrationFromJson('off'), CalibrationOption.off);
      expect(calibrationFromJson('auto'), CalibrationOption.auto);
    });

    test('warianty, które serwer sam akceptuje przy migracji', () {
      // _coerce_tristate przyjmuje 0/1/2 oraz "true"/"false" — czytanie kształtu,
      // który serwer jest gotów zapisać, nic nie kosztuje.
      expect(calibrationFromJson(0), CalibrationOption.off);
      expect(calibrationFromJson(1), CalibrationOption.on);
      expect(calibrationFromJson(2), CalibrationOption.auto);
      expect(calibrationFromJson('true'), CalibrationOption.on);
      expect(calibrationFromJson('false'), CalibrationOption.off);
    });

    test('wielkość litery i spacje nie mają znaczenia', () {
      expect(calibrationFromJson(' AUTO '), CalibrationOption.auto);
      expect(calibrationFromJson('On'), CalibrationOption.on);
    });

    test('brak wartości i śmieci → auto, nigdy wyjątek', () {
      for (final junk in [null, '', 'tak', 7, 3.5, <String>[], {}]) {
        expect(
          calibrationFromJson(junk),
          CalibrationOption.auto,
          reason: 'wejście: $junk',
        );
      }
    });

    test('calibrationOrNull rozróżnia „brak" od wartości', () {
      expect(calibrationOrNull(null), isNull);
      expect(calibrationOrNull('nonsens'), isNull);
      expect(calibrationOrNull(false), CalibrationOption.off);
    });
  });

  group('zapis', () {
    test('on/off zawsze jako boolean — rozumie każda wersja serwera', () {
      for (final triState in [true, false]) {
        expect(
          CalibrationOption.on.toWire(triState: triState),
          true,
          reason: 'triState=$triState',
        );
        expect(
          CalibrationOption.off.toWire(triState: triState),
          false,
          reason: 'triState=$triState',
        );
      }
    });

    test('auto jako string tylko tam, gdzie serwer ma to gdzie zapisać', () {
      expect(CalibrationOption.auto.toWire(triState: true), 'auto');
      expect(
        CalibrationOption.auto.toWire(triState: false),
        isNull,
        reason: 'null = klucz pominięty, nie zamiana auto na boolean',
      );
    });
  });

  group('kontrakt kolejki', () {
    // Regresja z produkcji: serwer 1.2.5 wysyła stringi, generowany rzut na
    // bool wywalał KAŻDY rekord, parseJsonList je pomijał i lista wychodziła
    // pusta przy poprawnym 200 (docs/plans/07-queue-cali-enum.md).
    Map<String, dynamic> record(Object bed, Object flow, Object nozzle) => {
      'id': 240,
      'position': 1,
      'status': 'pending',
      'bed_levelling': bed,
      'flow_cali': flow,
      'nozzle_offset_cali': nozzle,
      'vibration_cali': false,
      'preheat_override': 'inherit',
    };

    test('rekord z serwera 1.2.5 parsuje się, lista nie jest pusta', () {
      final items = parseJsonList([
        record('off', 'off', 'auto'),
      ], QueueItem.fromJson);
      expect(items, hasLength(1), reason: 'to jest ten pusty ekran');
      expect(items.single.bedLevelling, CalibrationOption.off);
      expect(items.single.flowCali, CalibrationOption.off);
      expect(items.single.nozzleOffsetCali, CalibrationOption.auto);
      expect(
        items.single.vibrationCali,
        isFalse,
        reason: 'vibration_cali migracji nie przeszło, zostaje boolean',
      );
    });

    test('rekord ze starszego serwera nadal parsuje się tak samo', () {
      final items = parseJsonList([
        record(true, false, true),
      ], QueueItem.fromJson);
      expect(items, hasLength(1));
      expect(items.single.bedLevelling, CalibrationOption.on);
      expect(items.single.flowCali, CalibrationOption.off);
      expect(items.single.nozzleOffsetCali, CalibrationOption.on);
    });

    test('obie postacie naraz nie wywalają całej listy', () {
      // Serwer w trakcie migracji rekordów: część wierszy stara, część nowa.
      final items = parseJsonList([
        record(true, false, true),
        record('auto', 'on', 'off'),
      ], QueueItem.fromJson);
      expect(items, hasLength(2));
    });

    test('brak kluczy kalibracji → auto, rekord zostaje', () {
      final items = parseJsonList([
        {'id': 1, 'position': 1, 'status': 'pending'},
      ], QueueItem.fromJson);
      expect(items, hasLength(1));
      expect(items.single.bedLevelling, CalibrationOption.auto);
    });
  });
}
