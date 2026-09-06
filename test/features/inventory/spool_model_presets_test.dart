import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/core/models/spool_preset_override.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ams_slot_config_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'dart:async';

import '../../helpers.dart';

/// The spool form's per-printer-model preset section. What matters here is what
/// leaves the phone: the route replaces the whole list, so a section nobody
/// touched must send nothing at all, and one that was touched must send every
/// row it holds — including the per-nozzle rows the web wrote, which this
/// screen shows but does not author.
class _FakeInventory extends InventoryNotifier {
  /// Every write the sheet made, in order, so a retry that creates a second
  /// spool instead of patching the first one shows up as an extra entry.
  final List<String> writes = [];

  @override
  Future<InventoryState> build() async => const InventoryState(
    spools: [Spool(id: 7, material: 'PLA', brand: 'Bambu')],
  );

  @override
  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) async {
    writes.add('update:$spoolId');
    return const Spool(id: 7, material: 'PLA');
  }

  @override
  Future<Spool?> createSpool(SpoolDraft draft) async {
    writes.add('create');
    return const Spool(id: 7, material: 'PLA');
  }
}

class _MockRepo extends Mock implements InventoryRepository {}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
    registerFallbackValue(const <SpoolPresetOverride>[]);
  });

  /// Opens the edit form for the one spool, with the fleet and the stored
  /// overrides the test wants behind it.
  Future<_MockRepo> openForm(
    WidgetTester tester, {
    List<String> models = const ['P1S', 'X1C'],
    List<SpoolPresetOverride> stored = const [],
    bool supported = true,
    Object? readFails,
    List<SlicerPreset> presets = const [],
    Future<List<SpoolPresetOverride>>? pendingRead,
    Object? writeFails,
    _FakeInventory? inventory,
    bool newSpool = false,
  }) async {
    final repo = _MockRepo();
    when(() => repo.savePresetOverrides(any(), any())).thenAnswer((_) async {
      if (writeFails != null) throw writeFails;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryProvider.overrideWith(() => inventory ?? _FakeInventory()),
          inventoryRepositoryProvider.overrideWithValue(repo),
          noServerProfileOverride,
          presetOverridesSupportedProvider.overrideWith((_) async => supported),
          printerModelsProvider.overrideWith((_) async => models),
          slicerPresetsProvider.overrideWith(
            (_) async => UnifiedPresets(
              printers: const [],
              processes: const [],
              filaments: presets,
            ),
          ),
          printerModelRegistryProvider.overrideWith(
            (_) async => const {'Bambu Lab P1S': 'P1S'},
          ),
          spoolPresetOverridesProvider(7).overrideWith((_) {
            if (pendingRead != null) return pendingRead;
            if (readFails != null) throw readFails;
            return stored;
          }),
        ],
        child: plApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openSpoolForm(
                  context,
                  existing: newSpool
                      ? null
                      : const Spool(id: 7, material: 'PLA', brand: 'Bambu'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    if (newSpool) {
      // Material is the one field the form refuses to save without, and on a
      // new spool it starts empty. It is the first combo in the sheet.
      await tester.enterText(
        find.descendant(
          of: find.byType(DropdownMenu<String>).first,
          matching: find.byType(TextField),
        ),
        'PLA',
      );
      // Typing into a combo opens its menu, and the menu's overlay covers the
      // rest of the sheet until it is dismissed.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
    }
    // The form is a lazy ListView taller than the screen — the section and the
    // save button below it are not built until they scroll into range.
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    return repo;
  }

  Finder saveButton() => find.widgetWithText(FilledButton, l10n.inventorySave);

  /// The section heading as `_FormSection` renders it — upper case.
  Finder heading() =>
      find.text(l10n.inventorySectionPrinterPresets.toUpperCase());

  testWidgets('offers one row per printer model in the fleet', (tester) async {
    await openForm(tester);

    expect(heading(), findsOneWidget);
    expect(find.text('P1S'), findsOneWidget);
    expect(find.text('X1C'), findsOneWidget);
    // Nothing overridden yet, so both rows say the spool's own preset applies.
    expect(find.text(l10n.inventoryPrinterPresetDefault), findsNWidgets(2));
  });

  testWidgets('a stored override shows the preset it names', (tester) async {
    await openForm(
      tester,
      stored: const [
        SpoolPresetOverride(
          printerModel: 'X1C',
          slicerFilament: 'GFA00',
          slicerFilamentName: 'Bambu PLA Basic @BBL X1C',
        ),
      ],
    );

    expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);
    expect(find.text(l10n.inventoryPrinterPresetDefault), findsOneWidget);
  });

  testWidgets('a per-nozzle row the web wrote keeps its own line, whatever '
      'the fleet reports', (tester) async {
    await openForm(
      tester,
      models: const ['X1C'],
      stored: const [
        SpoolPresetOverride(
          printerModel: 'H2D',
          nozzleDiameter: '0.2',
          slicerFilament: 'GFA01',
          slicerFilamentName: 'Bambu PLA Matte @BBL H2D 0.2 nozzle',
        ),
      ],
    );

    expect(
      find.text(l10n.inventoryPrinterPresetNozzle('H2D', '0.2')),
      findsOneWidget,
    );
  });

  testWidgets('an untouched section writes nothing — the route replaces the '
      'whole list', (tester) async {
    final repo = await openForm(
      tester,
      stored: const [
        SpoolPresetOverride(printerModel: 'X1C', slicerFilament: 'GFA00'),
      ],
    );

    await tester.tap(saveButton());
    await settle(tester);

    verifyNever(() => repo.savePresetOverrides(any(), any()));
  });

  testWidgets('a read that failed says so and offers no rows to edit', (
    tester,
  ) async {
    await openForm(tester, readFails: Exception('boom'));

    expect(find.text(l10n.inventoryPrinterPresetsLoadFailed), findsOneWidget);
    expect(find.text('P1S'), findsNothing);
  });

  testWidgets('a server without the routes has no section at all', (
    tester,
  ) async {
    await openForm(tester, supported: false);

    expect(heading(), findsNothing);
    expect(find.text('P1S'), findsNothing);
  });

  testWidgets('clearing a row drops it, and the save sends what is left', (
    tester,
  ) async {
    final repo = await openForm(
      tester,
      stored: const [
        SpoolPresetOverride(
          printerModel: 'X1C',
          slicerFilament: 'GFA00',
          slicerFilamentName: 'Bambu PLA Basic @BBL X1C',
        ),
        SpoolPresetOverride(
          printerModel: 'H2D',
          nozzleDiameter: '0.2',
          slicerFilament: 'GFA01',
          slicerFilamentName: 'Bambu PLA Matte @BBL H2D 0.2 nozzle',
        ),
      ],
    );

    await tester.tap(find.byIcon(Icons.clear).first);
    await settle(tester);
    await tester.tap(saveButton());
    await settle(tester);

    final sent =
        verify(() => repo.savePresetOverrides(7, captureAny())).captured.single
            as List<SpoolPresetOverride>;
    // The row the web wrote survives a clear on a different model: it is still
    // in the list the replace sends.
    expect(sent.map((o) => o.key), ['H2D|0.2']);
  });

  testWidgets('the picker opens narrowed to the row\'s model and the spool\'s '
      'material, and either filter can be switched off', (tester) async {
    await openForm(
      tester,
      models: const ['P1S'],
      presets: const [
        SlicerPreset(
          source: 'cloud',
          id: '1',
          name: 'Bambu PLA Basic @BBL P1S',
        ),
        SlicerPreset(source: 'cloud', id: '2', name: 'Bambu PETG HF @BBL P1S'),
        SlicerPreset(
          source: 'cloud',
          id: '3',
          name: 'Bambu PLA Basic @BBL X1C',
        ),
      ],
    );

    await tester.tap(find.text(l10n.inventoryPrinterPresetDefault));
    await settle(tester);

    // Only the preset that is both this model's and this spool's material.
    expect(find.text('Bambu PLA Basic @BBL P1S'), findsOneWidget);
    expect(find.text('Bambu PETG HF @BBL P1S'), findsNothing);
    expect(find.text('Bambu PLA Basic @BBL X1C'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'PLA'));
    await settle(tester);
    expect(find.text('Bambu PETG HF @BBL P1S'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'P1S'));
    await settle(tester);
    expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);
  });

  testWidgets('nothing is editable until the stored rows are in hand — a pick '
      'made first would be the whole list the save replaces with', (
    tester,
  ) async {
    final pending = Completer<List<SpoolPresetOverride>>();
    await openForm(tester, pendingRead: pending.future);

    // The section announces itself, but has no row to tap yet.
    expect(heading(), findsOneWidget);
    expect(find.text(l10n.inventoryPrinterPresetDefault), findsNothing);
    expect(find.text('P1S'), findsNothing);

    pending.complete(const [
      SpoolPresetOverride(
        printerModel: 'X1C',
        slicerFilament: 'GFA00',
        slicerFilamentName: 'Bambu PLA Basic @BBL X1C',
      ),
    ]);
    await settle(tester);

    expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);
    expect(find.text('P1S'), findsOneWidget);
  });

  testWidgets('a preset write that failed is retried against the spool that '
      'was just created, not by creating another', (tester) async {
    final fake = _FakeInventory();
    await openForm(
      tester,
      newSpool: true,
      inventory: fake,
      models: const ['P1S'],
      writeFails: Exception('boom'),
      presets: const [
        SlicerPreset(
          source: 'cloud',
          id: '1',
          name: 'Bambu PLA Basic @BBL P1S',
        ),
      ],
    );

    await tester.tap(find.text(l10n.inventoryPrinterPresetDefault));
    await settle(tester);
    await tester.tap(find.text('Bambu PLA Basic @BBL P1S'));
    await settle(tester);

    await tester.tap(saveButton());
    await settle(tester);
    // The spool is made; its presets are not, so the sheet stays open with the
    // pick still in it.
    expect(fake.writes, ['create']);
    expect(find.text('Bambu PLA Basic @BBL P1S'), findsOneWidget);

    await tester.tap(saveButton());
    await settle(tester);

    expect(fake.writes, ['create', 'update:7']);
  });
}
