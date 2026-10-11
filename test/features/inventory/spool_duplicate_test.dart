import 'dart:async';

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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers.dart';

class _FakeInventory extends InventoryNotifier {
  final List<String> writes = [];
  SpoolDraft? created;

  @override
  Future<InventoryState> build() async => InventoryState();

  @override
  Future<Spool?> createSpool(SpoolDraft draft) async {
    writes.add('create');
    created = draft;
    return const Spool(id: 8, material: 'PETG');
  }

  @override
  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) async {
    writes.add('update:$spoolId');
    return null;
  }
}

class _MockRepo extends Mock implements InventoryRepository {}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
    registerFallbackValue(const <SpoolPresetOverride>[]);
  });

  const source = Spool(
    id: 7,
    material: 'PETG',
    brand: 'Bambu Lab',
    subtype: 'HF',
    colorName: 'White',
    rgba: 'FFFFFFFF',
    labelWeight: 750,
    weightUsed: 400,
    lastScaleWeight: 600,
    costPerKg: 29.99,
    storageLocation: 'Shelf A',
    slicerFilament: 'GFG02',
    slicerFilamentName: 'Bambu PETG HF',
  );

  Future<(_FakeInventory, _MockRepo)> openCopy(
    WidgetTester tester, {
    Spool copyOf = source,
    bool presetsSupported = false,
    AsyncValue<bool>? gate,
    List<SpoolPresetOverride> stored = const [],
    Future<List<SpoolPresetOverride>>? pendingRead,
  }) async {
    final inventory = _FakeInventory();
    final repo = _MockRepo();
    when(() => repo.savePresetOverrides(any(), any())).thenAnswer((_) async {});
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openSpoolForm(context, copyOf: copyOf),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        inventoryProvider.overrideWith(() => inventory),
        inventoryRepositoryProvider.overrideWithValue(repo),
        noServerProfileOverride,
        presetOverridesSupportedProvider.overrideWithValue(
          gate ?? AsyncData(presetsSupported),
        ),
        printerModelsProvider.overrideWith((_) async => const ['X1C']),
        slicerPresetsProvider.overrideWith(
          (_) async =>
              const UnifiedPresets(printers: [], processes: [], filaments: []),
        ),
        printerModelRegistryProvider.overrideWith((_) async => const {}),
        spoolPresetOverridesProvider(
          copyOf.id,
        ).overrideWith((_) => pendingRead ?? Future.value(stored)),
      ],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return (inventory, repo);
  }

  Finder saveButton() => find.widgetWithText(FilledButton, l10n.inventorySave);

  /// The save button whatever it shows — a spinner while it waits.
  VoidCallback? saveAction(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed;

  Future<void> save(WidgetTester tester) async {
    await scrollSheetDown(tester);
    await tester.tap(saveButton());
    await settle(tester);
  }

  testWidgets('a duplicate is a new, full spool of the same filament', (
    tester,
  ) async {
    final (inventory, _) = await openCopy(tester);
    expect(find.text(l10n.inventoryNewSpool), findsOneWidget);
    await save(tester);

    expect(inventory.writes, ['create']);
    final draft = inventory.created!;
    expect(draft.material, 'PETG');
    expect(draft.brand, 'Bambu Lab');
    expect(draft.subtype, 'HF');
    expect(draft.colorName, 'White');
    expect(draft.rgba, 'FFFFFFFF');
    expect(draft.labelWeight, 750);
    expect(draft.costPerKg, 29.99);
    expect(draft.storageLocation, 'Shelf A');
    expect(draft.slicerFilament, 'GFG02');
    expect(draft.weightUsed, 0);
    expect(draft.lastScaleWeight, isNull);
  });

  testWidgets('a new spool stays full when its label weight changes', (
    tester,
  ) async {
    // The copied 750 g spool is really a 1 kg one: the remaining weight must
    // follow, or the new spool is saved with 250 g already used.
    final (inventory, _) = await openCopy(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.inventoryFieldLabelWeight),
      '1000',
    );
    await save(tester);

    expect(inventory.created!.labelWeight, 1000);
    expect(inventory.created!.weightUsed, 0);
  });

  testWidgets('a duplicate takes the per-model presets to the new spool', (
    tester,
  ) async {
    const x1c = SpoolPresetOverride(
      printerModel: 'X1C',
      slicerFilament: 'GFG02',
      slicerFilamentName: 'Bambu PETG HF @BBL X1C',
    );
    final (_, repo) = await openCopy(
      tester,
      presetsSupported: true,
      stored: const [x1c],
    );
    await save(tester);

    final written =
        verify(() => repo.savePresetOverrides(8, captureAny())).captured.single
            as List<SpoolPresetOverride>;
    expect(written.map((o) => o.key), [x1c.key]);
    verifyNever(() => repo.savePresetOverrides(7, any()));
  });

  testWidgets('a copy cannot be saved before its presets have arrived', (
    tester,
  ) async {
    final read = Completer<List<SpoolPresetOverride>>();
    await openCopy(tester, presetsSupported: true, pendingRead: read.future);
    await scrollSheetDown(tester);
    expect(saveAction(tester), isNull);

    read.complete(const []);
    await settle(tester);
    expect(saveAction(tester), isNotNull);
  });

  testWidgets('a copy waits for the presets gate too', (tester) async {
    await openCopy(tester, gate: const AsyncLoading());
    await scrollSheetDown(tester);
    expect(saveAction(tester), isNull);
  });

  testWidgets('a copy of a spool without a label weight gets 1000 g', (
    tester,
  ) async {
    final (inventory, _) = await openCopy(
      tester,
      copyOf: const Spool(id: 9, material: 'PLA'),
    );
    await save(tester);

    expect(inventory.created!.labelWeight, 1000);
    expect(inventory.created!.weightUsed, 0);
  });

  testWidgets('clearing a scale reading lets the label lead again', (
    tester,
  ) async {
    final (inventory, _) = await openCopy(tester);
    final measured = find.widgetWithText(
      TextFormField,
      l10n.inventoryFieldMeasuredWeight,
    );
    final label = find.widgetWithText(
      TextFormField,
      l10n.inventoryFieldLabelWeight,
    );
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(measured, 200, scrollable: list);
    await tester.enterText(measured, '1250');
    await tester.enterText(measured, '');
    await tester.scrollUntilVisible(label, -200, scrollable: list);
    await tester.enterText(label, '2000');
    await save(tester);

    expect(inventory.created!.labelWeight, 2000);
    expect(inventory.created!.weightUsed, 0);
  });
}
