import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trip preserves events and thresholds', () {
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

  test('unknown event names are skipped (forward compatibility)', () {
    final decoded = NotificationPrefs.decode(
        '{"enabled":["printFinished","futureEvent"]}');
    expect(decoded.enabled, {NotifEvent.printFinished});
    // thresholds fall back to defaults
    expect(decoded.bedCooledTemp, NotificationPrefs.defaultBedCooledTemp);
  });

  group('an event the writing build did not know', () {
    test("takes this build's default, not \"off\"", () {
      // Payload from an older build: it knew only two events, one of which the
      // user turned off. The rest had no switch there, so there is nothing to
      // inherit — they come in with the setting we ship them with.
      final decoded = NotificationPrefs.decode(
        '{"known":["printStarted","printFinished"],'
        '"enabled":["printStarted"]}',
      );

      expect(decoded.isOn(NotifEvent.printStarted), isTrue,
          reason: "user's choice");
      expect(decoded.isOn(NotifEvent.printFinished), isFalse,
          reason: 'user turned it off — even though it defaults to on');
      for (final e in NotifEvent.values) {
        if (e == NotifEvent.printStarted || e == NotifEvent.printFinished) {
          continue;
        }
        expect(decoded.isOn(e), NotificationPrefs.defaults.enabled.contains(e),
            reason: e.name);
      }
    });

    test('migration: a payload without the manifest leaves choices untouched',
        () {
      // A record written before the manifest comes from a build that knew
      // exactly the events listed below — so an empty list means "the user
      // turned everything off", not "those were new events". Otherwise an
      // update would switch them back on.
      //
      // This list is a copy of `_knownBeforeManifest` and the only structural
      // safeguard for it: that one is private, and its "do not add anything
      // here" comment is enforced by nothing. Adding a new event to it will
      // break this test — because a new event must come out here with its own
      // default, not as disabled. Do NOT fix that by adding it here too.
      const knownBeforeManifest = {
        NotifEvent.printStarted,
        NotifEvent.printFinished,
        NotifEvent.printFailed,
        NotifEvent.firstLayer,
        NotifEvent.milestones,
        NotifEvent.plateNotEmpty,
        NotifEvent.printerOffline,
        NotifEvent.printerError,
        NotifEvent.lowFilament,
        NotifEvent.amsHumidity,
        NotifEvent.bedCooled,
        NotifEvent.maintenanceDue,
      };
      final decoded = NotificationPrefs.decode('{"enabled":[]}');

      for (final e in NotifEvent.values) {
        expect(
          decoded.isOn(e),
          knownBeforeManifest.contains(e)
              ? isFalse
              : NotificationPrefs.defaults.enabled.contains(e),
          reason: e.name,
        );
      }
    });

    test('migration: a single pre-manifest choice survives the update', () {
      final decoded =
          NotificationPrefs.decode('{"enabled":["milestones"]}');

      expect(decoded.enabled, {NotifEvent.milestones});
    });

    test('the manifest round-trips and lists every event', () {
      const prefs = NotificationPrefs(enabled: {NotifEvent.bedCooled});
      final json = prefs.toJson();

      expect(json['known'], [for (final e in NotifEvent.values) e.name]);
      expect(NotificationPrefs.decode(prefs.encode()).enabled,
          {NotifEvent.bedCooled});
    });
  });

  test('corrupt/empty string → default prefs', () {
    expect(NotificationPrefs.decode(null).enabled,
        NotificationPrefs.defaults.enabled);
    expect(NotificationPrefs.decode('not json').enabled,
        NotificationPrefs.defaults.enabled);
  });

  test('withEvent turns a single event on and off', () {
    const base = NotificationPrefs(enabled: {});
    final on = base.withEvent(NotifEvent.lowFilament, true);
    expect(on.isOn(NotifEvent.lowFilament), isTrue);
    final off = on.withEvent(NotifEvent.lowFilament, false);
    expect(off.isOn(NotifEvent.lowFilament), isFalse);
  });

  test('master alertsEnabled=false mutes every event without losing choices',
      () {
    const prefs = NotificationPrefs(
      enabled: {NotifEvent.printFinished, NotifEvent.printerError},
      alertsEnabled: false,
    );
    // isOn returns false for everything...
    for (final e in NotifEvent.values) {
      expect(prefs.isOn(e), isFalse, reason: e.name);
    }
    // ...but the raw choices are kept and come back when it is switched on.
    expect(prefs.enabled, {NotifEvent.printFinished, NotifEvent.printerError});
    final reEnabled = prefs.copyWith(alertsEnabled: true);
    expect(reEnabled.isOn(NotifEvent.printFinished), isTrue);
    expect(reEnabled.isOn(NotifEvent.printerError), isTrue);
  });

  test('alertsEnabled round-trips; missing key → true (backwards)', () {
    const off = NotificationPrefs(enabled: {}, alertsEnabled: false);
    expect(NotificationPrefs.decode(off.encode()).alertsEnabled, isFalse);
    // Prefs written before the flag existed have no key → alerts stay on.
    expect(
        NotificationPrefs.decode('{"enabled":["printFinished"]}').alertsEnabled,
        isTrue);
  });

  test('finishPhoto round-trips; missing key → true (backwards)', () {
    const off = NotificationPrefs(enabled: {}, finishPhoto: false);
    expect(NotificationPrefs.decode(off.encode()).finishPhoto, isFalse);
    // An install from before this feature gets it on, not silently off.
    expect(
        NotificationPrefs.decode('{"enabled":["printFinished"]}').finishPhoto,
        isTrue);
    expect(NotificationPrefs.defaults.finishPhoto, isTrue);
  });
}
