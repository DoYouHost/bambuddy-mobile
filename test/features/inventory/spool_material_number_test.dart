import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The material number (#2870) on the shelf: shown, searched, filtered and
/// written. What leaves the phone is the point — a blank field on a new spool
/// must send nothing, so the server can fill in the number its other spools of
/// the product carry, while a blank over a stored number is a deliberate clear.
class _Shelf extends InventoryNotifier {
  _Shelf(this.spools);

  final List<Spool> spools;
  final drafts = <SpoolDraft>[];

  @override
  Future<InventoryState> build() async => InventoryState(spools: spools);

  @override
  Future<void> refresh({bool askBackend = false}) async {}

  @override
  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) async {
    drafts.add(draft);
    return null;
  }

  @override
  Future<Spool?> createSpool(SpoolDraft draft) async {
    drafts.add(draft);
    return const Spool(id: 99, material: 'PLA');
  }
}

const _alpha = Spool(
  id: 1,
  material: 'PLA',
  brand: 'Alpha',
  materialNumber: '15',
  materialNumberReported: true,
);
const _beta = Spool(
  id: 2,
  material: 'PLA',
  brand: 'Beta',
  materialNumber: 'A-104',
  materialNumberReported: true,
);
const _gamma = Spool(
  id: 3,
  material: 'PLA',
  brand: 'Gamma',
  materialNumberReported: true,
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  group('on the shelf', () {
    Future<void> pumpShelf(WidgetTester tester) async {
      await pumpPhone(
        tester,
        const InventoryScreen(),
        overrides: [
          inventoryProvider.overrideWith(() => _Shelf([_alpha, _beta, _gamma])),
          noServerProfileOverride,
        ],
      );
      await settle(tester);
    }

    testWidgets('a tile shows its number, a spool without one shows none', (
      tester,
    ) async {
      await pumpShelf(tester);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('A-104'), findsOneWidget);
    });

    testWidgets('the search finds a spool by its number', (tester) async {
      await pumpShelf(tester);
      await tester.enterText(byLogId('inventory.search'), 'a-10');
      await settle(tester);
      expect(find.textContaining('Beta'), findsOneWidget);
      expect(find.textContaining('Alpha'), findsNothing);
    });

    testWidgets('the filter lists the numbers in use and narrows by one', (
      tester,
    ) async {
      await pumpShelf(tester);
      await tester.tap(byLogId('inventory.filters'));
      await settle(tester);

      await scrollSheetDown(tester);
      expect(find.text(l10n.inventoryFieldMaterialNumber), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, '15'));
      await settle(tester);

      final filters = ProviderScope.containerOf(
        tester.element(find.byType(FilterChip).first),
      ).read(inventoryFiltersProvider);
      expect(filters.materialNumbers, {'15'});
      expect(filters.activeCount, 1);
      expect(filters.cleared().materialNumbers, isEmpty);
    });
  });

  group('in the form', () {
    Future<_Shelf> openForm(
      WidgetTester tester, {
      Spool? existing,
      bool supported = true,
      InventoryBackend backend = InventoryBackend.native,
    }) async {
      final shelf = _Shelf([_alpha, _beta]);
      await pumpPhone(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openSpoolForm(context, existing: existing),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: [
          inventoryProvider.overrideWith(() => shelf),
          noServerProfileOverride,
          inventoryRepositoryOf(backend),
          inventoryBackendOverride(backend),
          materialNumberSupportedProvider.overrideWithValue(
            AsyncData(supported),
          ),
          presetOverridesSupportedProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      if (existing == null) {
        await tester.enterText(
          find.descendant(
            of: find.byType(DropdownMenu<String>).first,
            matching: find.byType(TextField),
          ),
          'PLA',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
      }
      return shelf;
    }

    Future<void> save(WidgetTester tester) async {
      await scrollSheetDown(tester);
      await tester.tap(byLogId('spool_form.save'));
      await settle(tester);
    }

    testWidgets('an edit sends the number it was opened with', (tester) async {
      final shelf = await openForm(tester, existing: _alpha);
      await save(tester);
      expect(shelf.drafts.single.materialNumber, '15');
    });

    testWidgets('a typed number is trimmed and sent', (tester) async {
      final shelf = await openForm(tester, existing: _alpha);
      await tester.enterText(
        find.descendant(
          of: byLogId('spool_form.material_number'),
          matching: find.byType(TextField),
        ),
        '  22 ',
      );
      await save(tester);
      expect(shelf.drafts.single.materialNumber, '22');
    });

    testWidgets('blanking a stored number sends the empty string', (
      tester,
    ) async {
      final shelf = await openForm(tester, existing: _alpha);
      await tester.enterText(
        find.descendant(
          of: byLogId('spool_form.material_number'),
          matching: find.byType(TextField),
        ),
        '',
      );
      await save(tester);
      expect(shelf.drafts.single.materialNumber, '');
    });

    testWidgets('a blank number on a new spool sends nothing', (tester) async {
      final shelf = await openForm(tester);
      await save(tester);
      expect(shelf.drafts.single.materialNumber, isNull);
    });

    testWidgets('no field on a server without the feature', (tester) async {
      final shelf = await openForm(tester, existing: _alpha, supported: false);
      expect(byLogId('spool_form.material_number'), findsNothing);
      await save(tester);
      expect(shelf.drafts.single.materialNumber, isNull);
    });

    testWidgets('no field on Spoolman, where the number is read-only', (
      tester,
    ) async {
      final shelf = await openForm(
        tester,
        existing: _alpha,
        backend: InventoryBackend.spoolman,
      );
      expect(byLogId('spool_form.material_number'), findsNothing);
      await save(tester);
      expect(shelf.drafts.single.materialNumber, isNull);
    });
  });
}
