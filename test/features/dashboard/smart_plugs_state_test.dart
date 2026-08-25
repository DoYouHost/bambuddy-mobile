import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:flutter_test/flutter_test.dart';

SmartPlugStatus _status({String? state, bool? reachable, double? power}) =>
    SmartPlugStatus(
      state: state,
      reachable: reachable,
      energy: SmartPlugEnergy(power: power),
    );

/// A Home Assistant plug, the kind the ranking was written for.
SmartPlug _ha(
  int id, {
  required String entityId,
  int printerId = 5,
  bool? controlsPrinterPower,
  String? powerEntity,
  bool enabled = true,
  bool showOnPrinterCard = true,
}) =>
    SmartPlug(
      id: id,
      name: entityId,
      plugType: 'homeassistant',
      printerId: printerId,
      haEntityId: entityId,
      haPowerEntity: powerEntity,
      controlsPrinterPower: controlsPrinterPower,
      enabled: enabled,
      showOnPrinterCard: showOnPrinterCard,
    );

void main() {
  group('plugForPrinterCard', () {
    test('returns the assigned, visible plug', () {
      const plug = SmartPlug(
        id: 1,
        name: 'A',
        printerId: 5,
        enabled: true,
        showOnPrinterCard: true,
      );
      const state = SmartPlugsState(plugs: [plug]);
      expect(state.plugForPrinterCard(5), same(plug));
      expect(state.plugForPrinterCard(99), isNull);
    });

    test('skips disabled and hidden plugs', () {
      const disabled =
          SmartPlug(id: 1, printerId: 5, enabled: false, showOnPrinterCard: true);
      const hidden =
          SmartPlug(id: 2, printerId: 6, enabled: true, showOnPrinterCard: false);
      const state = SmartPlugsState(plugs: [disabled, hidden]);
      expect(state.plugForPrinterCard(5), isNull);
      expect(state.plugForPrinterCard(6), isNull);
    });

    test('never borrows a plug from another printer', () {
      const mine = SmartPlug(id: 2, printerId: 5);
      const theirs = SmartPlug(id: 1, printerId: 6);
      const state = SmartPlugsState(plugs: [theirs, mine]);
      expect(state.plugForPrinterCard(5), same(mine));
    });
  });

  // The reported stranding (#2830): an X1C with an exhaust fan added first and
  // the outlet the printer is actually plugged into second. The order mirrors
  // `routes/smart_plugs.py::_main_plug_rank`.
  group('plugForPrinterCard — main plug ranking', () {
    test('the outlet beats the fan that was listed first', () {
      final fan = _ha(1, entityId: 'switch.exhaust_fan', controlsPrinterPower: false);
      final outlet = _ha(
        2,
        entityId: 'switch.x1c_outlet',
        powerEntity: 'sensor.x1c_outlet_power',
      );
      final state = SmartPlugsState(plugs: [fan, outlet]);
      expect(state.plugForPrinterCard(5), same(outlet));
    });

    test('a switch beats a script', () {
      final script = _ha(1, entityId: 'script.start');
      final outlet = _ha(2, entityId: 'switch.outlet', controlsPrinterPower: false);
      final state = SmartPlugsState(plugs: [script, outlet]);
      expect(state.plugForPrinterCard(5), same(outlet));
    });

    test('a switchable plug beats a monitor-only MQTT plug', () {
      const monitor = SmartPlug(
        id: 1,
        name: 'Monitor',
        plugType: 'mqtt',
        printerId: 5,
        mqttPowerTopic: 'tele/printer/SENSOR',
      );
      final outlet = _ha(2, entityId: 'switch.outlet');
      const state = SmartPlugsState(plugs: [monitor]);
      expect(state.plugForPrinterCard(5), same(monitor), reason: 'alone it holds the row');
      expect(
        SmartPlugsState(plugs: [monitor, outlet]).plugForPrinterCard(5),
        same(outlet),
      );
    });

    test('a printer whose only plugs are scripts still gets one', () {
      final first = _ha(1, entityId: 'script.a');
      final second = _ha(2, entityId: 'script.b');
      final state = SmartPlugsState(plugs: [second, first]);
      expect(state.plugForPrinterCard(5), same(first));
    });

    test('reporting power only breaks a tie', () {
      final blind = _ha(1, entityId: 'switch.blind');
      final metered = _ha(
        2,
        entityId: 'switch.metered',
        powerEntity: 'sensor.metered_power',
      );
      expect(
        SmartPlugsState(plugs: [blind, metered]).plugForPrinterCard(5),
        same(metered),
      );

      // …but never over the printer-power flag: a metered accessory must not
      // take the row from the plug that feeds the printer.
      final accessory = _ha(
        3,
        entityId: 'switch.metered_fan',
        controlsPrinterPower: false,
        powerEntity: 'sensor.fan_power',
      );
      expect(
        SmartPlugsState(plugs: [accessory, blind]).plugForPrinterCard(5),
        same(blind),
      );
    });

    test('equal plugs fall back to the lowest id, whatever the list order', () {
      final second = _ha(7, entityId: 'switch.b');
      final first = _ha(3, entityId: 'switch.a');
      expect(
        SmartPlugsState(plugs: [second, first]).plugForPrinterCard(5),
        same(first),
      );
      expect(
        SmartPlugsState(plugs: [first, second]).plugForPrinterCard(5),
        same(first),
      );
    });

    test('a server too old for controls_printer_power ranks by the rest', () {
      // The field is absent, so every plug ties on it and the id decides —
      // exactly what such a server used to give us.
      const fan = SmartPlug(id: 1, name: 'Fan', printerId: 5);
      const outlet = SmartPlug(id: 2, name: 'Outlet', printerId: 5);
      const state = SmartPlugsState(plugs: [outlet, fan]);
      expect(state.plugForPrinterCard(5), same(fan));
    });
  });

  group('effectiveOn — precedence', () {
    const plug = SmartPlug(id: 1, printerId: 5, lastState: 'ON');

    test('the optimistic override wins over the status', () {
      final state = SmartPlugsState(
        plugs: const [plug],
        statuses: {1: _status(state: 'ON')},
        optimistic: const {1: false},
      );
      expect(state.effectiveOn(plug), isFalse);
    });

    test('the status wins over last_state from the config', () {
      final state = SmartPlugsState(
        plugs: const [plug],
        statuses: {1: _status(state: 'OFF')},
      );
      expect(state.effectiveOn(plug), isFalse); // despite lastState ON
    });

    test('falls back to last_state when there is no status', () {
      const state = SmartPlugsState(plugs: [plug]);
      expect(state.effectiveOn(plug), isTrue);
    });
  });

  group('totalPowerW', () {
    test('sums the power over reachable plugs', () {
      final state = SmartPlugsState(
        statuses: {
          1: _status(state: 'ON', reachable: true, power: 100),
          2: _status(state: 'ON', reachable: true, power: 55.5),
          3: _status(state: 'ON', reachable: false, power: 999), // skipped
        },
      );
      expect(state.totalPowerW, closeTo(155.5, 1e-9));
    });

    test('no plugs → 0 W and hasAnyPlug=false', () {
      const state = SmartPlugsState();
      expect(state.totalPowerW, 0);
      expect(state.hasAnyPlug, isFalse);
    });
  });
}
