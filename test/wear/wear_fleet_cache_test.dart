import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/wear/wear_fleet_cache.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wire map the relay hands the watch, which is the only shape this cache
/// ever stores — see [WearFleetCache].
Map<String, dynamic> _wire({
  int id = 1,
  String name = 'X1C',
  int? pending = 2,
}) => {
  'printers': [
    {
      'printer': {'id': id, 'name': name},
      'status': {'id': id, 'connected': true, 'progress': 42},
    },
  ],
  'queuePending': ?pending,
};

ServerProfile _profile([String url = 'http://one.local']) =>
    ServerProfile(baseUrl: url, authMode: AuthMode.none);

Future<SettingsRepository> _settings() async {
  SharedPreferences.setMockInitialValues({});
  return SettingsRepository(await SharedPreferences.getInstance());
}

void main() {
  late SettingsRepository settings;

  setUp(() async => settings = await _settings());

  test('a relayed fleet comes back parsed, and marked stale', () async {
    final cache = WearFleetCache(settings);
    await cache.save(wearFleetFromJson(_wire()), _profile());

    final restored = WearFleetCache(settings).load(_profile());

    expect(restored, isNotNull);
    expect(restored!.stale, isTrue, reason: 'the screens dim on this');
    expect(restored.printers.single.printer.name, 'X1C');
    expect(restored.printers.single.status?.progress, 42);
    expect(restored.queuePending, 2);
  });

  test('a fleet with no wire map behind it is not stored', () async {
    // What `RestTransport` produces: models, never JSON. Nothing to store, and
    // nothing that could be re-encoded — `PrinterStatus` has no `toJson`.
    const restFleet = WearFleet(printers: []);

    await WearFleetCache(settings).save(restFleet, _profile());

    expect(WearFleetCache(settings).load(_profile()), isNull);
  });

  test('a fleet cached against another server is refused', () async {
    await WearFleetCache(
      settings,
    ).save(wearFleetFromJson(_wire()), _profile('http://one.local'));

    // The watch adopts whatever server the phone pushes at it, so this is a
    // routine transition, not a corrupt file.
    expect(WearFleetCache(settings).load(_profile('http://two.local')), isNull);
  });

  test('an empty fleet is no better than no cache', () async {
    await WearFleetCache(
      settings,
    ).save(wearFleetFromJson(const {'printers': <Object>[]}), _profile());

    // "No printers" from last time would be a confident wrong answer; the
    // spinner it would have replaced at least admits to not knowing.
    expect(WearFleetCache(settings).load(_profile()), isNull);
  });

  test('a corrupt entry reads as no cache rather than throwing', () async {
    await settings.saveWearFleetCache('{not json');

    expect(WearFleetCache(settings).load(_profile()), isNull);
  });

  test('writes are floored at minInterval, and resume after it', () async {
    final start = DateTime(2026, 9, 16, 12);
    final cache = WearFleetCache(
      settings,
      minInterval: const Duration(minutes: 1),
    );

    await withClock(Clock.fixed(start), () async {
      await cache.save(wearFleetFromJson(_wire(name: 'first')), _profile());
    });
    // The 5-second poll that follows: nothing the next cold start would notice.
    await withClock(
      Clock.fixed(start.add(const Duration(seconds: 5))),
      () async {
        await cache.save(
          wearFleetFromJson(_wire(name: 'throttled')),
          _profile(),
        );
      },
    );

    expect(
      WearFleetCache(settings).load(_profile())!.printers.single.printer.name,
      'first',
    );

    await withClock(
      Clock.fixed(start.add(const Duration(minutes: 2))),
      () async {
        await cache.save(wearFleetFromJson(_wire(name: 'later')), _profile());
      },
    );

    expect(
      WearFleetCache(settings).load(_profile())!.printers.single.printer.name,
      'later',
    );
  });

  test('no profile means nothing is written and nothing is read', () async {
    final cache = WearFleetCache(settings);

    await cache.save(wearFleetFromJson(_wire()), null);

    expect(settings.loadWearFleetCache(), isNull);
    expect(cache.load(null), isNull);
  });
}
