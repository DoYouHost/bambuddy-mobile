import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trip zachowuje zdarzenia i progi', () {
    const prefs = NotificationPrefs(
      enabled: {NotifEvent.printStarted, NotifEvent.bedCooled},
      bedCooledTemp: 40,
      amsHumidityThreshold: 55,
      lowFilamentThreshold: 8,
    );
    final decoded = NotificationPrefs.decode(prefs.encode());
    expect(decoded.enabled, prefs.enabled);
    expect(decoded.bedCooledTemp, 40);
    expect(decoded.amsHumidityThreshold, 55);
    expect(decoded.lowFilamentThreshold, 8);
  });

  test('nieznane nazwy zdarzeń są pomijane (kompatybilność wprzód)', () {
    final decoded = NotificationPrefs.decode(
        '{"enabled":["printFinished","futureEvent"]}');
    expect(decoded.enabled, {NotifEvent.printFinished});
    // progi spadają do domyślnych
    expect(decoded.bedCooledTemp, NotificationPrefs.defaultBedCooledTemp);
  });

  test('uszkodzony/pusty string → domyślne prefs', () {
    expect(NotificationPrefs.decode(null).enabled,
        NotificationPrefs.defaults.enabled);
    expect(NotificationPrefs.decode('not json').enabled,
        NotificationPrefs.defaults.enabled);
  });

  test('withEvent włącza i wyłącza pojedyncze zdarzenie', () {
    const base = NotificationPrefs(enabled: {});
    final on = base.withEvent(NotifEvent.lowFilament, true);
    expect(on.isOn(NotifEvent.lowFilament), isTrue);
    final off = on.withEvent(NotifEvent.lowFilament, false);
    expect(off.isOn(NotifEvent.lowFilament), isFalse);
  });

  test('master alertsEnabled=false wycisza wszystkie zdarzenia bez utraty wyborów',
      () {
    const prefs = NotificationPrefs(
      enabled: {NotifEvent.printFinished, NotifEvent.printerError},
      alertsEnabled: false,
    );
    // isOn zwraca false dla wszystkiego...
    for (final e in NotifEvent.values) {
      expect(prefs.isOn(e), isFalse, reason: e.name);
    }
    // ...ale surowe wybory są zachowane i wracają po ponownym włączeniu.
    expect(prefs.enabled, {NotifEvent.printFinished, NotifEvent.printerError});
    final reEnabled = prefs.copyWith(alertsEnabled: true);
    expect(reEnabled.isOn(NotifEvent.printFinished), isTrue);
    expect(reEnabled.isOn(NotifEvent.printerError), isTrue);
  });

  test('alertsEnabled przechodzi round-trip; brak klucza → true (wstecz)', () {
    const off = NotificationPrefs(enabled: {}, alertsEnabled: false);
    expect(NotificationPrefs.decode(off.encode()).alertsEnabled, isFalse);
    // Prefs zapisane przed dodaniem flagi nie mają klucza → alerty włączone.
    expect(
        NotificationPrefs.decode('{"enabled":["printFinished"]}').alertsEnabled,
        isTrue);
  });

  test('finishPhoto przechodzi round-trip; brak klucza → true (wstecz)', () {
    const off = NotificationPrefs(enabled: {}, finishPhoto: false);
    expect(NotificationPrefs.decode(off.encode()).finishPhoto, isFalse);
    // Instalacja sprzed tej funkcji dostaje ją włączoną, nie po cichu wyłączoną.
    expect(
        NotificationPrefs.decode('{"enabled":["printFinished"]}').finishPhoto,
        isTrue);
    expect(NotificationPrefs.defaults.finishPhoto, isTrue);
  });
}
