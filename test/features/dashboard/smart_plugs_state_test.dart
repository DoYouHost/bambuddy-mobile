import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:flutter_test/flutter_test.dart';

SmartPlugStatus _status({String? state, bool? reachable, double? power}) =>
    SmartPlugStatus(
      state: state,
      reachable: reachable,
      energy: SmartPlugEnergy(power: power),
    );

void main() {
  group('plugForPrinterCard', () {
    test('zwraca przypisane, widoczne gniazdko', () {
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

    test('pomija wyłączone i ukryte', () {
      const disabled =
          SmartPlug(id: 1, printerId: 5, enabled: false, showOnPrinterCard: true);
      const hidden =
          SmartPlug(id: 2, printerId: 6, enabled: true, showOnPrinterCard: false);
      const state = SmartPlugsState(plugs: [disabled, hidden]);
      expect(state.plugForPrinterCard(5), isNull);
      expect(state.plugForPrinterCard(6), isNull);
    });
  });

  group('effectiveOn — precedencja', () {
    const plug = SmartPlug(id: 1, printerId: 5, lastState: 'ON');

    test('optymistyczne nadpisanie wygrywa ze statusem', () {
      final state = SmartPlugsState(
        plugs: const [plug],
        statuses: {1: _status(state: 'ON')},
        optimistic: const {1: false},
      );
      expect(state.effectiveOn(plug), isFalse);
    });

    test('status wygrywa z last_state z konfiguracji', () {
      final state = SmartPlugsState(
        plugs: const [plug],
        statuses: {1: _status(state: 'OFF')},
      );
      expect(state.effectiveOn(plug), isFalse); // mimo lastState ON
    });

    test('fallback na last_state gdy brak statusu', () {
      const state = SmartPlugsState(plugs: [plug]);
      expect(state.effectiveOn(plug), isTrue);
    });
  });

  group('totalPowerW', () {
    test('sumuje moc po osiągalnych gniazdkach', () {
      final state = SmartPlugsState(
        statuses: {
          1: _status(state: 'ON', reachable: true, power: 100),
          2: _status(state: 'ON', reachable: true, power: 55.5),
          3: _status(state: 'ON', reachable: false, power: 999), // pomijane
        },
      );
      expect(state.totalPowerW, closeTo(155.5, 1e-9));
    });

    test('brak gniazdek → 0 W i hasAnyPlug=false', () {
      const state = SmartPlugsState();
      expect(state.totalPowerW, 0);
      expect(state.hasAnyPlug, isFalse);
    });
  });
}
