import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fields the printer card's main-plug ranking reads, straight off
/// `SmartPlugResponse`. They decide which plug gets the power button, so a
/// silently mis-parsed key would hand it to an exhaust fan.
void main() {
  group('SmartPlug.fromJson — ranking fields', () {
    test('reads the Home Assistant keys', () {
      final plug = SmartPlug.fromJson(const {
        'id': 7,
        'name': 'X1C Outlet',
        'plug_type': 'homeassistant',
        'ha_entity_id': 'switch.x1c_outlet',
        'ha_power_entity': 'sensor.x1c_outlet_power',
        'controls_printer_power': true,
      });

      expect(plug.haEntityId, 'switch.x1c_outlet');
      expect(plug.controlsPrinterPower, isTrue);
      expect(plug.isHaScript, isFalse);
      expect(plug.canBeSwitched, isTrue);
      expect(plug.reportsPower, isTrue);
    });

    test('a server without controls_printer_power leaves it unknown', () {
      final plug = SmartPlug.fromJson(const {'id': 1, 'plug_type': 'tasmota'});

      expect(plug.controlsPrinterPower, isNull);
      expect(plug.canBeSwitched, isTrue);
      // Tasmota firmware reports watts when the hardware has it.
      expect(plug.reportsPower, isTrue);
    });
  });

  group('canBeSwitched', () {
    test('a Home Assistant script is not a switch', () {
      const script = SmartPlug(
        id: 1,
        plugType: 'homeassistant',
        haEntityId: 'script.start_print',
      );
      expect(script.isHaScript, isTrue);
      expect(script.canBeSwitched, isFalse);
      // …but the card may still run it: only MQTT is refused outright.
      expect(script.isMonitorOnly, isFalse);
    });

    test('an MQTT plug is monitor-only', () {
      const monitor =
          SmartPlug(id: 1, plugType: 'mqtt', mqttPowerTopic: 'tele/x1c/SENSOR');
      expect(monitor.isMonitorOnly, isTrue);
      expect(monitor.canBeSwitched, isFalse);
    });

    test('a light or an input_boolean is', () {
      const light = SmartPlug(
        id: 1,
        plugType: 'homeassistant',
        haEntityId: 'light.chamber',
      );
      expect(light.canBeSwitched, isTrue);
    });
  });

  // `last_state` (config) and `state` (live status) share one vocabulary,
  // because each plug type words the same thing differently.
  group('on/off state', () {
    test('reads every spelling the plug types use', () {
      for (final on in ['ON', 'on', 'TRUE', 'true', '1']) {
        expect(SmartPlug(id: 1, lastState: on).lastIsOn, isTrue, reason: on);
        expect(SmartPlugStatus(state: on).isOn, isTrue, reason: on);
      }
      for (final off in ['OFF', 'off', 'FALSE', 'false', '0']) {
        expect(SmartPlug(id: 1, lastState: off).lastIsOn, isFalse, reason: off);
        expect(SmartPlugStatus(state: off).isOn, isFalse, reason: off);
      }
    });

    test('anything else is unknown, not off', () {
      for (final unknown in [null, '', 'unavailable', '2']) {
        expect(SmartPlug(id: 1, lastState: unknown).lastIsOn, isNull,
            reason: '$unknown');
        expect(SmartPlugStatus(state: unknown).isOn, isNull, reason: '$unknown');
      }
    });
  });

  group('reportsPower', () {
    test('Home Assistant needs a power sensor', () {
      const blind =
          SmartPlug(id: 1, plugType: 'homeassistant', haEntityId: 'switch.a');
      expect(blind.reportsPower, isFalse);
    });

    test('MQTT accepts the legacy topic as well', () {
      const legacy = SmartPlug(id: 1, plugType: 'mqtt', mqttTopic: 'tele/x1c/SENSOR');
      expect(legacy.reportsPower, isTrue);
      expect(const SmartPlug(id: 2, plugType: 'mqtt').reportsPower, isFalse);
    });

    test('REST needs a path to read watts from', () {
      const metered =
          SmartPlug(id: 1, plugType: 'rest', restPowerPath: 'meters.0.power');
      expect(metered.reportsPower, isTrue);
      expect(const SmartPlug(id: 2, plugType: 'rest').reportsPower, isFalse);
    });
  });
}
