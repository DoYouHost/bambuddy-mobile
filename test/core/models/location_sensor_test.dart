import 'package:bambuddy_mobile/core/models/location_sensor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocationSensorReading numeric(double? value, {String? unit = '°C'}) =>
      LocationSensorReading.fromJson({
        'id': 1,
        'name': 'Temperature',
        'entity_id': 'sensor.dry_box_temperature',
        'kind': 'numeric',
        'device_class': 'temperature',
        'unit': unit,
        'state': value?.toString(),
        'value': value,
      });

  group('formattedValue', () {
    test('a whole number carries no decimal place', () {
      expect(numeric(24).formattedValue, '24°C');
      expect(numeric(-3).formattedValue, '-3°C');
    });

    test('a fraction keeps one, and the second is rounded away', () {
      expect(numeric(24.4).formattedValue, '24.4°C');
      expect(numeric(47.24).formattedValue, '47.2°C');
      expect(numeric(47.25).formattedValue, '47.3°C');
      expect(numeric(-3.55).formattedValue, '-3.6°C');
    });

    test('a fraction that rounds to a whole number loses the place too', () {
      expect(numeric(23.98).formattedValue, '24°C');
    });

    test('a hair below zero is at zero, not "-0"', () {
      // Rounding keeps the sign, so a drybox in a cold room reported -0.04 °C
      // as being below freezing.
      expect(numeric(-0.04).formattedValue, '0°C');
      expect(numeric(-0.049).formattedValue, '0°C');
      // And a reading that really is below it still says so.
      expect(numeric(-0.06).formattedValue, '-0.1°C');
      expect(numeric(-1).formattedValue, '-1°C');
    });

    test('an entity that reports no unit is shown as a bare number', () {
      expect(numeric(1013.2, unit: null).formattedValue, '1013.2');
    });

    test('nothing readable has no value to format', () {
      expect(numeric(null).formattedValue, isNull);
    });

    test('a binary sensor has no number at all — its state is the reading', () {
      final door = LocationSensorReading.fromJson({
        'id': 2,
        'name': 'Door',
        'entity_id': 'binary_sensor.dry_box_door',
        'kind': 'binary',
        'state': 'on',
      });

      expect(door.numeric, isFalse);
      expect(door.formattedValue, isNull);
      expect(door.isOn, isTrue);
    });
  });

  group('category', () {
    test('the three the server keys its one-per-location rule on', () {
      for (final (deviceClass, expected) in [
        ('temperature', LocationSensorCategory.temperature),
        ('humidity', LocationSensorCategory.humidity),
        ('battery', LocationSensorCategory.battery),
      ]) {
        expect(
          LocationSensorCategory.fromDeviceClass(deviceClass),
          expected,
        );
      }
    });

    test('anything else is shown by its own name, icon-less', () {
      // `moisture` is Home Assistant's wet/dry binary class, which the server
      // deliberately does not treat as humidity — a leak detector must not
      // shadow a hygrometer on the same shelf.
      expect(
        LocationSensorCategory.fromDeviceClass('moisture'),
        LocationSensorCategory.other,
      );
      expect(
        LocationSensorCategory.fromDeviceClass('carbon_dioxide'),
        LocationSensorCategory.other,
      );
      expect(
        LocationSensorCategory.fromDeviceClass(null),
        LocationSensorCategory.other,
      );
      expect(
        LocationSensorCategory.fromDeviceClass(''),
        LocationSensorCategory.other,
      );
    });
  });

  group('reachable', () {
    test('a payload that omits it is not passed off as fresh', () {
      expect(numeric(24).reachable, isFalse);
    });

    test('and one that says so is', () {
      final fresh = LocationSensorReading.fromJson({
        'id': 1,
        'name': 'Temperature',
        'kind': 'numeric',
        'reachable': true,
      });

      expect(fresh.reachable, isTrue);
    });
  });
}
