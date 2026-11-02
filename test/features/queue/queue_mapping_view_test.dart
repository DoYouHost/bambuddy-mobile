import 'dart:async';

import 'package:bambuddy_mobile/core/ams/color_names.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// What the mapping sheet says about each filament and slot, as the web's
/// `FilamentMapping.tsx` says it: the verdict up top, the filament by its
/// catalogue name with its nozzle and grams, each slot as
/// `A1: <spool or variant> (<colour>)`, and why a pick is not a match.
class _Printers extends PrintersRepository {
  _Printers(this._status, [this._spools = const {}, this._answer])
    : super(Dio());

  final PrinterStatus _status;
  final Map<int, SlotSpool> _spools;

  /// Holds the status back until completed, to look at the sheet meanwhile.
  final Completer<void>? _answer;

  @override
  Future<PrinterStatus?> fetchStatus(int printerId) async {
    await _answer?.future;
    return _status;
  }

  @override
  Future<SlotInventory> fetchInventoryRemain(int printerId) async =>
      (grams: const <int, double>{}, spools: _spools);
}

AmsTray _tray(int id, String type, String color, {String? subBrands}) =>
    AmsTray(id: id, trayType: type, trayColor: color, traySubBrands: subBrands);

void main() {
  Future<void> open(
    WidgetTester tester, {
    required PrinterStatus status,
    List<FilamentRequirement> requirements = const [
      FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
    ],
    Map<int, SlotSpool> spools = const {},
    ColorCatalog catalog = ColorCatalog.empty,
    Map<String, String> names = const {},
    List<int>? stored,
    Completer<void>? answer,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeServerProfileOverride(),
          printersRepositoryProvider.overrideWithValue(
            _Printers(status, spools, answer),
          ),
          inventoryBackendOverride(),
          inventoryProvider.overrideWith(
            () => FixedInventory(InventoryState()),
          ),
          serverSettingsOverride(const {}),
          printRequirementsProvider.overrideWith(
            (ref, key) async => requirements,
          ),
          mappingColorCatalogProvider.overrideWith((ref) async => catalog),
          mappingFilamentNamesProvider.overrideWith((ref) async => names),
          mappingColorByMaterialProvider.overrideWith((ref, key) async => null),
        ],
        child: plApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showQueueMappingSheet(
                context,
                item: QueueItem(
                  id: 1,
                  position: 1,
                  status: 'pending',
                  archiveId: 5,
                  amsMapping: stored,
                ),
                printerId: 1,
                confirmLabel: 'OK',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  PrinterStatus amsOf(List<AmsTray> trays, {Map<int, String>? inlets}) =>
      PrinterStatus(
        id: 1,
        ams: [AmsUnit(id: 0, trays: trays)],
        amsSwitchInlet: inlets,
        filaSwitch: inlets == null
            ? null
            : const FilaSwitch(installed: true, ready: true),
      );

  testWidgets(
    'waiting for the printer, the sheet is no taller than its spinner',
    (tester) async {
      usePhoneWindow(tester);
      final answer = Completer<void>();
      await open(
        tester,
        status: amsOf([_tray(0, 'PLA', 'FF0000FF')]),
        answer: answer,
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSize(find.byType(BottomSheet)).height,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
        ),
        reason: 'a Center spinner takes the whole height a sheet offers',
      );
      answer.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a match reads ready, with the slot and its colour', (
    tester,
  ) async {
    // Two trays: a unit reporting one is an AMS-HT to the web (`HT-A`).
    await open(
      tester,
      status: amsOf([
        _tray(0, 'PLA', 'FF0000FF'),
        _tray(1, 'PETG', '000000FF'),
      ]),
    );

    expect(find.text(pl.mappingStatusReady), findsOneWidget);
    expect(find.text('A1: PLA (Czerwony)'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('another colour of the type says which two colours', (
    tester,
  ) async {
    await open(tester, status: amsOf([_tray(0, 'PLA', '00FF00FF')]));

    expect(find.text(pl.mappingStatusColorMismatch), findsOneWidget);
    expect(
      find.text(pl.mappingSameTypeOtherColor('Czerwony', 'Zielony')),
      findsOneWidget,
    );
  });

  testWidgets('colours that read alike get their hex', (tester) async {
    // Both are "Czerwony" by family; the hex is what differs (#2941).
    await open(tester, status: amsOf([_tray(0, 'PLA', 'A00000FF')]));

    expect(
      find.text(
        pl.mappingSameTypeOtherColor(
          'Czerwony (#FF0000)',
          'Czerwony (#A00000)',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no slot of the type reads type not found', (tester) async {
    await open(tester, status: amsOf([_tray(0, 'PETG', 'FF0000FF')]));

    expect(find.text(pl.mappingStatusTypeNotFound), findsOneWidget);
    expect(find.text(pl.mappingTypeNotLoaded), findsOneWidget);
  });

  testWidgets('a slot goes by its spool, else by the variant and catalogue', (
    tester,
  ) async {
    await open(
      tester,
      status: amsOf([
        _tray(0, 'PLA', 'FF8000FF'),
        _tray(1, 'PLA', 'FFFFFFFF', subBrands: 'PLA Matte'),
      ]),
      spools: const {0: (name: 'Devil Design PLA Basic', colorName: 'Orange')},
      catalog: ColorCatalog.fromJson(const {
        'colors': {'ffffff': 'Jade White'},
        'by_material': {'PLA Matte|#FFFFFF': 'Ivory White'},
      }),
    );
    await tester.tap(find.text('PLA').first);
    await tester.pumpAndSettle();

    expect(find.text('A1: Devil Design PLA Basic (Orange)'), findsWidgets);
    expect(find.text('A2: PLA Matte (Ivory White)'), findsOneWidget);
  });

  testWidgets('a filament goes by its catalogue name, nozzle and grams', (
    tester,
  ) async {
    await open(
      tester,
      status: amsOf([_tray(0, 'PLA', 'FF0000FF')]),
      requirements: const [
        FilamentRequirement(
          slotId: 1,
          type: 'PLA',
          color: '#FF0000',
          trayInfoIdx: 'GFA00',
          nozzleId: 1,
          usedGrams: 12.4,
        ),
      ],
      names: const {'GFA00': 'Bambu PLA Basic'},
    );

    expect(find.text('Bambu PLA Basic'), findsOneWidget);
    expect(find.text(pl.extruderLeftShort), findsOneWidget);
    expect(find.text(' (12\u00A0g)'), findsOneWidget);
  });

  testWidgets('the picker marks the exact colour and the switch inlet', (
    tester,
  ) async {
    await open(
      tester,
      status: amsOf([_tray(0, 'PLA', 'FF0000FF')], inlets: const {0: 'A'}),
    );
    await tester.tap(find.text('PLA').first);
    await tester.pumpAndSettle();

    expect(find.text('[L] · ${pl.mappingExactColor}'), findsOneWidget);
  });

  testWidgets('a stored pick says it was picked by hand', (tester) async {
    await open(
      tester,
      status: amsOf([_tray(0, 'PLA', 'FF0000FF'), _tray(1, 'PLA', 'FF0000FF')]),
      stored: [1],
    );

    expect(find.text(pl.mappingManual), findsOneWidget);
  });

  group('the Filament Track Switch inlet', () {
    const two = [
      FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
      FilamentRequirement(slotId: 2, type: 'PETG', color: '#00FF00'),
    ];
    const warning =
        'Wszystkie filamenty tego wydruku są na wlocie IN-A przełącznika '
        'Filament Track Switch.';

    testWidgets('one inlet for every filament is the slow case', (
      tester,
    ) async {
      await open(
        tester,
        requirements: two,
        status: amsOf(
          [_tray(0, 'PLA', 'FF0000FF'), _tray(1, 'PETG', '00FF00FF')],
          inlets: const {0: 'A'},
        ),
      );

      expect(find.textContaining(warning), findsOneWidget);
    });

    testWidgets('two inlets are not', (tester) async {
      await open(
        tester,
        requirements: two,
        status: const PrinterStatus(
          id: 1,
          ams: [
            AmsUnit(
              id: 0,
              trays: [
                AmsTray(id: 0, trayType: 'PLA', trayColor: 'FF0000FF'),
                AmsTray(id: 1, trayType: 'ABS', trayColor: '000000FF'),
              ],
            ),
            AmsUnit(
              id: 1,
              trays: [
                AmsTray(id: 0, trayType: 'PETG', trayColor: '00FF00FF'),
                AmsTray(id: 1, trayType: 'ABS', trayColor: '000000FF'),
              ],
            ),
          ],
          amsSwitchInlet: {0: 'A', 1: 'B'},
          filaSwitch: FilaSwitch(installed: true, ready: true),
        ),
      );

      expect(find.textContaining('IN-'), findsNothing);
    });

    testWidgets('no switch, no inlet', (tester) async {
      await open(
        tester,
        requirements: two,
        status: amsOf([
          _tray(0, 'PLA', 'FF0000FF'),
          _tray(1, 'PETG', '00FF00FF'),
        ]),
      );

      expect(find.textContaining('IN-'), findsNothing);
    });
  });
}
