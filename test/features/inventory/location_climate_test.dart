import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/core/models/location_sensor.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/data/location_sensors_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The storage-conditions readings, which the app shows in the two places a
/// spool and its shelf are both on screen: the spool's own card, and the sheet
/// behind the Filaments app bar.
class _Shelf extends InventoryNotifier {
  _Shelf(this._spools);

  final List<Spool> _spools;

  @override
  Future<InventoryState> build() async => InventoryState(spools: _spools);
}

/// Records what the provider actually asks for: the point of the listing is
/// that a location nobody bound a sensor to is never asked for a reading.
class _FakeSensors extends LocationSensorsRepository {
  _FakeSensors({
    required this.bindings,
    required this.readingsByLocation,
    this.supported = true,
  }) : super(Dio());

  final List<LocationSensorBinding> bindings;
  final Map<int, List<LocationSensorReading>> readingsByLocation;
  final bool supported;

  final asked = <int>[];

  @override
  Future<bool> supportsLocationSensors() async => supported;

  @override
  Future<List<LocationSensorBinding>> listBindings() async => bindings;

  @override
  Future<List<LocationSensorReading>> readings(int locationId) async {
    asked.add(locationId);
    return readingsByLocation[locationId] ?? const [];
  }
}

void main() {
  const dryBox = StorageLocation(id: 3, name: 'Dry box', spoolCount: 2);

  const spool = Spool(
    id: 128,
    material: 'PETG',
    brand: 'Polymaker',
    labelWeight: 1000,
    weightUsed: 340,
    storageLocation: 'Dry box',
  );

  LocationSensorReading reading({
    required String name,
    required String deviceClass,
    required double value,
    String unit = '%',
    bool alerting = false,
    bool reachable = true,
  }) => LocationSensorReading(
    id: value.round(),
    name: name,
    entityId: 'sensor.dry_box_$deviceClass',
    numeric: true,
    deviceClass: deviceClass,
    unit: unit,
    state: '$value',
    value: value,
    alerting: alerting,
    reachable: reachable,
  );

  final climate = LocationClimate(
    location: dryBox,
    readings: [
      reading(
        name: 'Temperature',
        deviceClass: 'temperature',
        value: 24.0,
        unit: '°C',
      ),
      reading(
        name: 'Humidity',
        deviceClass: 'humidity',
        value: 47.2,
        alerting: true,
      ),
      reading(
        name: 'Battery',
        deviceClass: 'battery',
        value: 78,
        reachable: false,
      ),
    ],
  );

  /// The same shelf with nothing out of range — the app bar has to read
  /// differently for the two, and colour is not what a screen reader gets.
  final calmClimate = LocationClimate(
    location: dryBox,
    readings: [
      reading(
        name: 'Temperature',
        deviceClass: 'temperature',
        value: 24.0,
        unit: '°C',
      ),
    ],
  );

  Future<void> pumpShelf(
    WidgetTester tester, {
    Map<String, LocationClimate> climates = const {},
    List<Spool> spools = const [spool],
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryProvider.overrideWith(() => _Shelf(spools)),
          locationClimateProvider.overrideWith((ref) async => climates),
          noServerProfileOverride,
        ],
        child: plApp(const InventoryScreen()),
      ),
    );
    await settle(tester);
  }

  testWidgets("a spool's card says what its shelf reads right now", (
    tester,
  ) async {
    await pumpShelf(tester, climates: {'dry box': climate});

    await tester.tap(find.text('Polymaker PETG'));
    await settle(tester);

    expect(
      find.text('Temperature 24°C'),
      findsOneWidget,
      reason: 'a whole number needs no decimal place',
    );
    expect(find.text('Humidity 47.2%'), findsOneWidget);
    // The unreachable one keeps its last value and trades its icon for the
    // struck-through sensor, which is the whole of how it says "not current".
    expect(find.text('Battery 78%'), findsOneWidget);
    expect(find.byIcon(Icons.sensors_off), findsOneWidget);
    expect(find.byIcon(Icons.thermostat), findsWidgets);
  });

  testWidgets('a spool on a shelf with no sensor shows no pills', (
    tester,
  ) async {
    await pumpShelf(tester);

    await tester.tap(find.text('Polymaker PETG'));
    await settle(tester);

    expect(find.textContaining('Humidity'), findsNothing);
    expect(find.byIcon(Icons.sensors_off), findsNothing);
  });

  testWidgets('the app bar offers nothing when no shelf is measured', (
    tester,
  ) async {
    await pumpShelf(tester);

    expect(find.byIcon(Icons.thermostat), findsNothing);
  });

  testWidgets('a shelf within range reads as plain storage conditions', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('pl'));

    await pumpShelf(tester, climates: {'dry box': calmClimate});

    expect(find.byTooltip(l10n.inventoryClimateTitle), findsOneWidget);
  });

  testWidgets('the app bar says an alert out loud, not only in amber', (
    tester,
  ) async {
    // The amber ink is the whole of how the icon shows this to a sighted user,
    // and a tooltip is an icon button's semantic label — so the sentence has
    // to change with the colour.
    final l10n = await AppLocalizations.delegate.load(const Locale('pl'));

    await pumpShelf(tester, climates: {'dry box': climate});

    expect(find.byTooltip(l10n.inventoryClimateTitleAlerting), findsOneWidget);
    expect(find.byTooltip(l10n.inventoryClimateTitle), findsNothing);
  });

  testWidgets('the app bar opens the sheet where a sensor is bound', (
    tester,
  ) async {
    await pumpShelf(tester, climates: {'dry box': climate});

    expect(find.byIcon(Icons.thermostat), findsOneWidget);

    await tester.tap(find.byIcon(Icons.thermostat));
    await settle(tester);

    expect(find.text('Dry box'), findsOneWidget);
    expect(find.text('Humidity 47.2%'), findsOneWidget);
  });

  group('locationClimateProvider', () {
    const shelfA = StorageLocation(id: 1, name: 'Shelf A', spoolCount: 4);

    LocationSensorBinding binding(int id, int locationId, {bool card = true}) =>
        LocationSensorBinding(id: id, locationId: locationId, showOnCard: card);

    Future<(Map<String, LocationClimate>, _FakeSensors)> resolve(
      _FakeSensors sensors, {
      List<StorageLocation> catalog = const [shelfA, dryBox],
    }) async {
      final container = ProviderContainer(
        overrides: [
          locationSensorsRepositoryProvider.overrideWithValue(sensors),
          locationCatalogProvider.overrideWith((ref) async => catalog),
        ],
      );
      addTearDown(container.dispose);
      return (await container.read(locationClimateProvider.future), sensors);
    }

    test('asks only the locations something is bound to', () async {
      final (climates, sensors) = await resolve(
        _FakeSensors(
          bindings: [binding(1, dryBox.id)],
          readingsByLocation: {dryBox.id: climate.readings},
        ),
      );

      expect(sensors.asked, [dryBox.id]);
      expect(climates.keys, ['dry box']);
      expect(climates['dry box']!.location.name, 'Dry box');
      expect(climates['dry box']!.alerting, isTrue);
    });

    test(
      'a sensor the server hides from the card is not one to ask about',
      () async {
        final (climates, sensors) = await resolve(
          _FakeSensors(
            bindings: [binding(1, dryBox.id, card: false)],
            readingsByLocation: {dryBox.id: climate.readings},
          ),
        );

        expect(sensors.asked, isEmpty);
        expect(climates, isEmpty);
      },
    );

    test('a location whose readings come back empty is left out', () async {
      final (climates, _) = await resolve(
        _FakeSensors(
          bindings: [binding(1, shelfA.id)],
          readingsByLocation: const {},
        ),
      );

      expect(climates, isEmpty);
    });

    test(
      'a binding naming a location the catalog does not have is skipped',
      () async {
        final (climates, sensors) = await resolve(
          _FakeSensors(
            bindings: [binding(1, 99)],
            readingsByLocation: {99: climate.readings},
          ),
          catalog: const [shelfA],
        );

        expect(sensors.asked, isEmpty);
        expect(climates, isEmpty);
      },
    );

    test('an older server is not asked at all', () async {
      final (climates, sensors) = await resolve(
        _FakeSensors(
          supported: false,
          bindings: [binding(1, dryBox.id)],
          readingsByLocation: {dryBox.id: climate.readings},
        ),
      );

      expect(sensors.asked, isEmpty);
      expect(climates, isEmpty);
    });
  });

  group('climateOfSpool', () {
    test('matches the shelf however the spool spells it', () {
      final climates = {'dry box': climate};

      for (final written in ['Dry box', ' dry BOX ', 'DRY BOX']) {
        expect(
          climateOfSpool(
            climates,
            Spool(id: 1, material: 'PLA', storageLocation: written),
          ),
          same(climate),
          reason: 'the server keys location names on LOWER(TRIM(name))',
        );
      }
    });

    test('a spool with no location, or one nobody measures, has none', () {
      final climates = {'dry box': climate};

      expect(
        climateOfSpool(climates, const Spool(id: 1, material: 'PLA')),
        isNull,
      );
      expect(
        climateOfSpool(
          climates,
          const Spool(id: 1, material: 'PLA', storageLocation: '  '),
        ),
        isNull,
      );
      expect(
        climateOfSpool(
          climates,
          const Spool(id: 1, material: 'PLA', storageLocation: 'Shelf B'),
        ),
        isNull,
      );
    });
  });
}
