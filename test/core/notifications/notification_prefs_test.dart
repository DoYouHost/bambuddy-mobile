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

  group('zdarzenie, którego zapisujący build nie znał', () {
    test('bierze domyślną wartość tego buildu, nie „wyłączone"', () {
      // Payload starszego buildu: znał tylko dwa zdarzenia, jedno z nich user
      // wyłączył. Reszta nie miała tam przełącznika, więc nie ma czego
      // dziedziczyć — wchodzi z ustawieniem, z jakim ją wydajemy.
      final decoded = NotificationPrefs.decode(
        '{"known":["printStarted","printFinished"],'
        '"enabled":["printStarted"]}',
      );

      expect(decoded.isOn(NotifEvent.printStarted), isTrue, reason: 'wybór usera');
      expect(decoded.isOn(NotifEvent.printFinished), isFalse,
          reason: 'user go wyłączył — mimo że domyślnie jest włączone');
      for (final e in NotifEvent.values) {
        if (e == NotifEvent.printStarted || e == NotifEvent.printFinished) {
          continue;
        }
        expect(decoded.isOn(e), NotificationPrefs.defaults.enabled.contains(e),
            reason: e.name);
      }
    });

    test('migracja: payload bez znacznika zostawia wybory nietknięte', () {
      // Zapis sprzed znacznika pochodzi z buildu, który znał komplet dzisiejszych
      // zdarzeń — więc pusta lista znaczy „user wyłączył wszystko", a nie „to
      // były nowe zdarzenia". Inaczej aktualizacja włączyłaby je z powrotem.
      final decoded = NotificationPrefs.decode('{"enabled":[]}');

      for (final e in NotifEvent.values) {
        expect(decoded.isOn(e), isFalse, reason: e.name);
      }
    });

    test('migracja: pojedynczy wybór sprzed znacznika przeżywa aktualizację', () {
      final decoded =
          NotificationPrefs.decode('{"enabled":["milestones"]}');

      expect(decoded.enabled, {NotifEvent.milestones});
    });

    test('znacznik przechodzi round-trip i wymienia komplet zdarzeń', () {
      const prefs = NotificationPrefs(enabled: {NotifEvent.bedCooled});
      final json = prefs.toJson();

      expect(json['known'], [for (final e in NotifEvent.values) e.name]);
      expect(NotificationPrefs.decode(prefs.encode()).enabled,
          {NotifEvent.bedCooled});
    });
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
