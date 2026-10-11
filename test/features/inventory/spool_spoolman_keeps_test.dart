import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Spoolman changes a spool's brand and price but cannot empty them: its route
/// keeps the old value on null and on an empty string. A form that let the user
/// blank them would report a removal that never happens.
class _Shelf extends InventoryNotifier {
  final drafts = <SpoolDraft>[];

  @override
  Future<InventoryState> build() async => InventoryState();

  @override
  Future<void> refresh({bool askBackend = false}) async {}

  @override
  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) async {
    drafts.add(draft);
    return null;
  }
}

const _spool = Spool(id: 7, material: 'PLA', brand: 'Bambu', costPerKg: 20.5);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<_Shelf> openForm(WidgetTester tester, InventoryBackend backend) async {
    final shelf = _Shelf();
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openSpoolForm(context, existing: _spool),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        inventoryProvider.overrideWith(() => shelf),
        noServerProfileOverride,
        inventoryRepositoryOf(backend),
        inventoryBackendOverride(backend),
        presetOverridesSupportedProvider.overrideWithValue(
          const AsyncData(false),
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return shelf;
  }

  Finder inputOf(String id) =>
      find.descendant(of: byLogId(id), matching: find.byType(TextField));

  Future<void> save(WidgetTester tester) async {
    await scrollSheetDown(tester);
    await tester.tap(byLogId('spool_form.save'));
    await settle(tester);
  }

  testWidgets('Spoolman: a blanked brand is refused and nothing is sent', (
    tester,
  ) async {
    final shelf = await openForm(tester, InventoryBackend.spoolman);
    await tester.enterText(inputOf('spool_form.brand'), '');
    await tester.pump();

    expect(find.text(l10n.inventorySpoolmanCannotClear), findsOneWidget);
    await save(tester);
    expect(shelf.drafts, isEmpty);
  });

  testWidgets('Spoolman: a blanked price is refused too', (tester) async {
    final shelf = await openForm(tester, InventoryBackend.spoolman);
    await scrollSheetDown(tester, times: 3);
    await tester.enterText(inputOf('spool_form.cost_per_kg'), '');
    await tester.pump();

    expect(find.text(l10n.inventorySpoolmanCannotClear), findsOneWidget);
    await save(tester);
    expect(shelf.drafts, isEmpty);
  });

  testWidgets('Spoolman: changing the brand to another value is saved', (
    tester,
  ) async {
    final shelf = await openForm(tester, InventoryBackend.spoolman);
    await tester.enterText(inputOf('spool_form.brand'), 'Polymaker');
    await tester.pump();

    expect(find.text(l10n.inventorySpoolmanCannotClear), findsNothing);
    await save(tester);
    expect(shelf.drafts.single.brand, 'Polymaker');
  });

  testWidgets('built-in inventory: a blanked brand is cleared, not refused', (
    tester,
  ) async {
    final shelf = await openForm(tester, InventoryBackend.native);
    await tester.enterText(inputOf('spool_form.brand'), '');
    await tester.pump();

    expect(find.text(l10n.inventorySpoolmanCannotClear), findsNothing);
    await save(tester);
    expect(shelf.drafts.single.clears, contains('brand'));
  });
}
