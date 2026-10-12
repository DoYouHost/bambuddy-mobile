import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'fake_suppliers.dart';

/// The last drying (#2863) on the shelf: a mark on the tile that costs the
/// list no height, and the run's figures in the detail sheet.
class _Shelf extends InventoryNotifier {
  _Shelf(this.spools);

  final List<Spool> spools;
  final drafts = <SpoolDraft>[];

  @override
  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) async {
    drafts.add(draft);
    // What the server answers: the spool as this write left it.
    return Spool(id: spoolId, material: draft.material, suppliers: const []);
  }

  @override
  Future<InventoryState> build() async => InventoryState(spools: spools);

  @override
  Future<void> refresh({bool askBackend = false}) async {}
}

// Local, as the model holds it (`dateTimeFromJson`): a UTC fixture would be
// formatted as another day in a zone far enough east.
final _dried = DateTime(2026, 10, 6, 12);

Spool _spool(int id, String brand, {DateTime? at, int? temp, double? hours}) =>
    Spool(
      id: id,
      material: 'PLA',
      brand: brand,
      lastDriedAt: at,
      lastDriedTemp: temp,
      lastDriedHours: hours,
      lastDriedReported: true,
    );

void main() {
  group('lastDriedRun', () {
    // The web's formatLastDriedDetails: whole hours drop their decimal, the
    // rest rounds to one; a date set by hand has no figures to name.
    final cases = <String, (Spool, String?)>{
      'temperature and hours': (
        _spool(1, 'A', temp: 55, hours: 7.5),
        '55 °C · 7.5 h',
      ),
      'whole hours': (_spool(1, 'A', temp: 50, hours: 8), '50 °C · 8 h'),
      'rounded down': (_spool(1, 'A', hours: 7.54), '7.5 h'),
      'rounded up to whole': (_spool(1, 'A', hours: 7.96), '8 h'),
      'hours without a temperature': (_spool(1, 'A', hours: 4), '4 h'),
      'a date set by hand': (_spool(1, 'A', at: _dried), null),
    };
    cases.forEach((name, c) {
      test(name, () => expect(lastDriedRun(c.$1), c.$2));
    });
  });

  group('on the shelf', () {
    final shelf = [
      _spool(1, 'Alpha', at: _dried, temp: 55, hours: 7.5),
      _spool(2, 'Beta'),
    ];

    Future<void> pumpShelf(WidgetTester tester, {bool supported = true}) async {
      await pumpPhone(
        tester,
        const InventoryScreen(),
        overrides: [
          inventoryProvider.overrideWith(() => _Shelf(shelf)),
          noServerProfileOverride,
          lastDriedSupportedProvider.overrideWithValue(AsyncData(supported)),
        ],
      );
      await settle(tester);
    }

    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(byLogId('inventory.filters'));
      await settle(tester);
    }

    testWidgets('the sort is offered where the server records a drying', (
      tester,
    ) async {
      await pumpShelf(tester);
      await openFilters(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, pl.inventoryLastDried));
      await settle(tester);
      final filters = ProviderScope.containerOf(
        tester.element(find.byType(InventoryScreen)),
      ).read(inventoryFiltersProvider);
      expect(filters.sort, InventorySort.lastDried);
    });

    testWidgets(
      'a sort already chosen stays on its chip when the gate closes',
      (tester) async {
        await pumpShelf(tester, supported: false);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(InventoryScreen)),
        );
        container.read(inventoryFiltersProvider.notifier).state = container
            .read(inventoryFiltersProvider)
            .copyWith(sort: InventorySort.lastDried);
        await openFilters(tester);
        final chip = find.widgetWithText(ChoiceChip, pl.inventoryLastDried);
        expect(chip, findsOneWidget);
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      },
    );

    testWidgets('an older server is not offered a sort with nothing to order', (
      tester,
    ) async {
      await pumpShelf(tester, supported: false);
      await openFilters(tester);
      expect(
        find.widgetWithText(ChoiceChip, pl.inventoryLastDried),
        findsNothing,
      );
      expect(
        find.widgetWithText(ChoiceChip, pl.inventorySortAdded),
        findsOneWidget,
      );
    });

    testWidgets('a dried spool carries its date on the tile, others none', (
      tester,
    ) async {
      await pumpShelf(tester);
      final formats = DateTimeFormats.of(
        tester.element(find.byType(InventoryScreen)),
      );
      expect(find.text(formats.dayNamedMonth(_dried)), findsOneWidget);
      expect(find.byIcon(Icons.air), findsOneWidget);
    });

    testWidgets('the sheet gives the date and the run', (tester) async {
      await pumpShelf(tester);
      await tester.tap(find.textContaining('Alpha'));
      await settle(tester);
      final formats = DateTimeFormats.of(
        tester.element(find.byType(InventoryScreen)),
      );
      expect(find.text(pl.inventoryLastDried), findsOneWidget);
      expect(
        find.text('${formats.date(_dried)} · 55 °C · 7.5 h'),
        findsOneWidget,
      );
    });

    testWidgets('a spool never dried has no such row', (tester) async {
      await pumpShelf(tester);
      await tester.tap(find.textContaining('Beta'));
      await settle(tester);
      expect(find.text(pl.inventoryLastDried), findsNothing);
    });
  });

  group('SpoolDraft', () {
    const base = SpoolDraft(material: 'PLA');
    final at = DateTime.utc(2026, 10, 6, 12, 30);

    test('a date typed by hand goes out with its Z, on both backends', () {
      final draft = SpoolDraft(material: 'PLA', lastDriedAt: at);
      expect(draft.toNativeJson()['last_dried_at'], '2026-10-06T12:30:00.000Z');
      expect(
        draft.toSpoolmanJson()['last_dried_at'],
        '2026-10-06T12:30:00.000Z',
      );
    });

    test('a local time is sent as the same instant in UTC', () {
      final draft = SpoolDraft(material: 'PLA', lastDriedAt: at.toLocal());
      expect(draft.toNativeJson()['last_dried_at'], '2026-10-06T12:30:00.000Z');
    });

    test('an untouched draft keeps the key off the wire', () {
      expect(base.toNativeJson().containsKey('last_dried_at'), isFalse);
      expect(base.toSpoolmanJson().containsKey('last_dried_at'), isFalse);
    });

    test('clearing it goes out as an explicit null on both backends', () {
      const draft = SpoolDraft(material: 'PLA', clears: {'last_dried_at'});
      expect(draft.toNativeJson()['last_dried_at'], isNull);
      expect(draft.toNativeJson().containsKey('last_dried_at'), isTrue);
      expect(draft.toSpoolmanJson().containsKey('last_dried_at'), isTrue);
      expect(draft.toSpoolmanJson()['last_dried_at'], isNull);
    });

    test('a blank draft over a dried spool does not clear the date', () {
      // The server stamps it while a form is open; only the form may name it.
      final stored = _spool(1, 'A', at: at);
      final draft = base.clearing(stored);
      expect(draft.clears.contains('last_dried_at'), isFalse);
      expect(draft.toNativeJson().containsKey('last_dried_at'), isFalse);
    });

    test('clearing() carries a typed date through', () {
      final draft = SpoolDraft(
        material: 'PLA',
        lastDriedAt: at,
      ).clearing(_spool(1, 'A'));
      expect(draft.lastDriedAt, at);
    });
  });

  group('in the form', () {
    final dried = _spool(1, 'Alpha', at: _dried, temp: 55, hours: 7.5);

    Future<_Shelf> openForm(
      WidgetTester tester, {
      Spool? existing,
      bool supported = true,
      InventoryBackend backend = InventoryBackend.native,
      FakeSuppliers? suppliers,
    }) async {
      final shelf = _Shelf([dried]);
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
          lastDriedSupportedProvider.overrideWithValue(AsyncData(supported)),
          if (suppliers != null)
            suppliersRepositoryProvider.overrideWithValue(suppliers),
          presetOverridesSupportedProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      // The sheet's list builds lazily: without this the field is not there
      // yet, and every "no field" test below would pass for the wrong reason.
      await scrollSheetDown(tester);
      return shelf;
    }

    Future<void> save(WidgetTester tester) async {
      await scrollSheetDown(tester);
      await tester.tap(byLogId('spool_form.save'));
      await settle(tester);
    }

    testWidgets('saving an unrelated edit sends no date', (tester) async {
      final shelf = await openForm(tester, existing: dried);
      expect(byLogId('spool_form.last_dried'), findsOneWidget);
      await save(tester);
      expect(shelf.drafts.single.lastDriedAt, isNull);
      expect(shelf.drafts.single.clears.contains('last_dried_at'), isFalse);
    });

    testWidgets('the hint wraps instead of being cut to one line', (
      tester,
    ) async {
      await openForm(tester, existing: dried);
      final hint = find.text(pl.inventoryLastDriedHelp);
      await tester.ensureVisible(hint);
      expect(
        tester.renderObject<RenderParagraph>(hint).didExceedMaxLines,
        isFalse,
      );
      // The same 11 pt tertiary line as the field's own helper text, not the
      // 13 pt body copy it was set in once.
      expect(
        tester.widget<Text>(hint).style,
        DashTokens.of(tester.element(hint)).microSoft,
      );
    });

    testWidgets('Now sets the date to the present moment', (tester) async {
      final shelf = await openForm(tester, existing: dried);
      final before = DateTime.now();
      await tester.ensureVisible(find.text(pl.inventoryLastDriedNow));
      await tester.tap(find.text(pl.inventoryLastDriedNow));
      await settle(tester);
      await save(tester);
      final sent = shelf.drafts.single.lastDriedAt!;
      expect(sent.difference(before).inSeconds.abs(), lessThan(60));
    });

    testWidgets('the cross empties it, and that is named as a clear', (
      tester,
    ) async {
      final shelf = await openForm(tester, existing: dried);
      await tester.ensureVisible(find.byTooltip(pl.clear));
      await tester.tap(find.byTooltip(pl.clear));
      await settle(tester);
      await save(tester);
      expect(shelf.drafts.single.lastDriedAt, isNull);
      expect(shelf.drafts.single.clears.contains('last_dried_at'), isTrue);
    });

    testWidgets(
      'a retry after a failed follow-up does not send the date again',
      (tester) async {
        // An AMS run can finish while the sheet is open; a second PATCH naming
        // the date would drop that run's figures.
        final suppliers = FakeSuppliers(
          suppliers: const [Supplier(id: 5, name: 'Filamentworld')],
        );
        final shelf = await openForm(
          tester,
          existing: Spool(
            id: 3,
            material: 'PLA',
            suppliers: const [],
            lastDriedAt: _dried,
            lastDriedReported: true,
          ),
          suppliers: suppliers,
        );
        await tester.ensureVisible(find.text(pl.inventoryLastDriedNow));
        await tester.tap(find.text(pl.inventoryLastDriedNow));
        await settle(tester);
        await tester.tap(byLogId('spool_form.supplier_add'));
        await settle(tester);
        await tester.tap(find.text('Filamentworld'));
        await settle(tester);

        suppliers.failNextWrite = conflict;
        await save(tester);
        expect(shelf.drafts.single.lastDriedAt, isNotNull);

        await save(tester);
        expect(shelf.drafts, hasLength(2));
        expect(shelf.drafts.last.lastDriedAt, isNull);
        expect(shelf.drafts.last.clears.contains('last_dried_at'), isFalse);
      },
    );

    testWidgets('a spool never dried has no cross, only Now', (tester) async {
      await openForm(tester, existing: _spool(2, 'Beta'));
      expect(find.byTooltip(pl.clear), findsNothing);
      await tester.ensureVisible(find.text(pl.inventoryLastDriedNow));
      expect(find.text(pl.inventoryLastDriedNow), findsOneWidget);
    });

    testWidgets('an older server is not offered the field', (tester) async {
      await openForm(tester, existing: dried, supported: false);
      expect(byLogId('spool_form.last_dried'), findsNothing);
    });

    testWidgets('a new spool has no drying to record', (tester) async {
      await openForm(tester);
      expect(byLogId('spool_form.last_dried'), findsNothing);
    });

    testWidgets('Spoolman offers it too', (tester) async {
      final shelf = await openForm(
        tester,
        existing: dried,
        backend: InventoryBackend.spoolman,
      );
      expect(byLogId('spool_form.last_dried'), findsOneWidget);
      await save(tester);
      expect(shelf.drafts, hasLength(1));
    });
  });
}
