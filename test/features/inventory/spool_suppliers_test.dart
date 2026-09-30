import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'fake_suppliers.dart';

/// A spool's supplier assignments: where its product can be bought, and which
/// of those places it came from. What leaves the phone is the point — the
/// route replaces the whole list, and a new spool that sends nothing is given
/// the assignments of another spool of the same product by the server.
class _FakeInventory extends InventoryNotifier {
  _FakeInventory([this.spools = const []]);

  final List<Spool> spools;
  final writes = <String>[];

  @override
  Future<InventoryState> build() async => InventoryState(spools: spools);

  @override
  Future<void> refresh() async {}

  @override
  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) async {
    writes.add('update:$spoolId');
    return null;
  }

  @override
  Future<Spool?> createSpool(SpoolDraft draft) async {
    writes.add('create');
    return const Spool(id: 8, material: 'PLA');
  }
}

const _extrudr = SpoolSupplierLink(
  supplierId: 3,
  supplierName: 'Extrudr',
  articleNumber: 'NX2-1',
  quotedPricePerKg: 24.5,
  isPurchaseSource: true,
);
const _shop = SpoolSupplierLink(supplierId: 5, supplierName: 'Filamentworld');

const _linked = Spool(
  id: 7,
  material: 'PLA',
  brand: 'Bambu',
  suppliers: [_extrudr, _shop],
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<(FakeSuppliers, _FakeInventory)> openForm(
    WidgetTester tester, {
    Spool? existing = _linked,
    Spool? copyOf,
    bool supported = true,
    List<Supplier> master = const [],
    InventoryBackend backend = InventoryBackend.native,
  }) async {
    final suppliers = FakeSuppliers(suppliers: master, supported: supported);
    final inventory = _FakeInventory();
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openSpoolForm(
              context,
              existing: copyOf == null ? existing : null,
              copyOf: copyOf,
            ),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        inventoryProvider.overrideWith(() => inventory),
        noServerProfileOverride,
        suppliersRepositoryProvider.overrideWithValue(suppliers),
        // Never called: the preset section is off, so nothing reaches it.
        inventoryRepositoryProvider.overrideWithValue(
          InventoryRepository(NativeInventorySource(Dio())),
        ),
        inventoryBackendOverride(backend),
        presetOverridesSupportedProvider.overrideWithValue(
          const AsyncData(false),
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    if (existing == null && copyOf == null) {
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
    await scrollSheetDown(tester);
    return (suppliers, inventory);
  }

  Future<void> save(WidgetTester tester) async {
    await scrollSheetDown(tester);
    await tester.tap(byLogId('spool_form.save'));
    await settle(tester);
  }

  testWidgets('no section on a server without suppliers', (tester) async {
    await openForm(tester, supported: false);
    expect(find.text(l10n.inventorySupplierLinksHint), findsNothing);
  });

  testWidgets('the supplier cards line up with each other and the button', (
    tester,
  ) async {
    await openForm(tester);

    // The close icon's edge is where the fields end, not wherever its touch
    // box happens to leave it.
    final icon = tester.getTopRight(find.byIcon(Icons.close).first).dx;
    final field = tester
        .getTopRight(byLogId('spool_form.supplier_price').first)
        .dx;
    expect(icon, field);

    final card = find
        .ancestor(of: find.text('Extrudr'), matching: find.byType(Container))
        .first;
    final button = byLogId('spool_form.supplier_add');
    expect(tester.getTopLeft(button).dx, tester.getTopLeft(card).dx);
    expect(tester.getTopRight(button).dx, tester.getTopRight(card).dx);
  });

  testWidgets('an untouched edit writes nothing', (tester) async {
    final (suppliers, inventory) = await openForm(tester);
    expect(find.text('Extrudr'), findsOneWidget);
    expect(find.text('Filamentworld'), findsOneWidget);

    await save(tester);

    expect(inventory.writes, ['update:7']);
    expect(suppliers.savedLinks, isEmpty);
  });

  testWidgets('moving the purchase source clears it on the other link', (
    tester,
  ) async {
    final (suppliers, _) = await openForm(tester);

    await tester.tap(byLogId('spool_form.supplier_bought_here').last);
    await tester.pump();
    await save(tester);

    final (id, links, backend) = suppliers.savedLinks.single;
    expect(id, 7);
    expect(backend, InventoryBackend.native);
    expect(links.map((l) => l.supplierId), [3, 5]);
    expect(links.map((l) => l.isPurchaseSource), [false, true]);
    // The fields the user did not touch go back as they came.
    expect(links.first.articleNumber, 'NX2-1');
    expect(links.first.quotedPricePerKg, 24.5);
  });

  testWidgets('a removed link is left out, on the Spoolman route too', (
    tester,
  ) async {
    final (suppliers, _) = await openForm(
      tester,
      backend: InventoryBackend.spoolman,
    );

    await tester.tap(byLogId('spool_form.supplier_remove').first);
    await tester.pump();
    await save(tester);

    final (_, links, backend) = suppliers.savedLinks.single;
    expect(backend, InventoryBackend.spoolman);
    expect(links.map((l) => l.supplierId), [5]);
  });

  testWidgets('a typed price and article number are sent, blanks as null', (
    tester,
  ) async {
    final (suppliers, _) = await openForm(tester);

    await tester.enterText(byLogId('spool_form.supplier_price').last, '19,9');
    await tester.enterText(byLogId('spool_form.supplier_article').first, ' ');
    await save(tester);

    final (_, links, _) = suppliers.savedLinks.single;
    expect(links.last.quotedPricePerKg, 19.9);
    expect(links.first.articleNumber, isNull);
  });

  testWidgets('a negative price is refused before anything is sent', (
    tester,
  ) async {
    final (suppliers, inventory) = await openForm(tester);

    await tester.enterText(byLogId('spool_form.supplier_price').last, '-2');
    await save(tester);

    expect(find.text(l10n.inventoryFieldNegative), findsOneWidget);
    expect(inventory.writes, isEmpty);
    expect(suppliers.savedLinks, isEmpty);
  });

  testWidgets('an untouched new spool leaves the server to inherit', (
    tester,
  ) async {
    final (suppliers, inventory) = await openForm(tester, existing: null);
    await save(tester);

    expect(inventory.writes, ['create']);
    expect(suppliers.savedLinks, isEmpty);
  });

  testWidgets('a copy takes the sources but not where the original was '
      'bought', (tester) async {
    final (suppliers, inventory) = await openForm(tester, copyOf: _linked);
    await save(tester);

    expect(inventory.writes, ['create']);
    final (id, links, _) = suppliers.savedLinks.single;
    expect(id, 8);
    expect(links.map((l) => l.supplierId), [3, 5]);
    expect(links.every((l) => !l.isPurchaseSource), isTrue);
    expect(links.first.articleNumber, 'NX2-1');
  });

  testWidgets('the first supplier picked becomes where it was bought', (
    tester,
  ) async {
    final (suppliers, _) = await openForm(
      tester,
      existing: const Spool(id: 7, material: 'PLA', suppliers: []),
      master: const [
        Supplier(id: 3, name: 'Extrudr'),
        Supplier(id: 5, name: 'Filamentworld'),
      ],
    );

    await tester.tap(byLogId('spool_form.supplier_add'));
    await settle(tester);
    await tester.tap(find.text('Filamentworld'));
    await settle(tester);
    await save(tester);

    final (_, links, _) = suppliers.savedLinks.single;
    expect(links.single.supplierId, 5);
    expect(links.single.isPurchaseSource, isTrue);
  });

  testWidgets('the picker offers only suppliers the spool does not have', (
    tester,
  ) async {
    await openForm(
      tester,
      master: const [
        Supplier(id: 3, name: 'Extrudr'),
        Supplier(id: 5, name: 'Filamentworld'),
        Supplier(id: 9, name: 'Printed Solid'),
      ],
    );

    await tester.tap(byLogId('spool_form.supplier_add'));
    await settle(tester);

    expect(byLogId('supplier_picker.option'), findsOneWidget);
    expect(find.text('Printed Solid'), findsOneWidget);
  });

  testWidgets('a supplier created from the picker lands on the spool', (
    tester,
  ) async {
    final (suppliers, _) = await openForm(
      tester,
      existing: const Spool(id: 7, material: 'PLA', suppliers: []),
    );

    await tester.tap(byLogId('spool_form.supplier_add'));
    await settle(tester);
    expect(find.text(l10n.inventorySupplierNoneLeft), findsOneWidget);
    await tester.tap(byLogId('supplier_picker.new'));
    await settle(tester);
    await tester.enterText(
      find.ancestor(
        of: find.text('${l10n.inventorySupplierFieldName} *'),
        matching: find.byType(TextFormField),
      ),
      'Prusament',
    );
    await tester.ensureVisible(byLogId('supplier_form.save'));
    await settle(tester);
    await tester.tap(byLogId('supplier_form.save'));
    await settle(tester);
    await save(tester);

    expect(suppliers.created.single.name, 'Prusament');
    final (_, links, _) = suppliers.savedLinks.single;
    expect(links.single.supplierName, 'Prusament');
  });

  group('outside the form', () {
    Future<void> pumpShelf(WidgetTester tester, List<Spool> spools) async {
      await pumpPhone(
        tester,
        const InventoryScreen(),
        overrides: [
          inventoryProvider.overrideWith(() => _FakeInventory(spools)),
          noServerProfileOverride,
          suppliersRepositoryProvider.overrideWithValue(FakeSuppliers()),
        ],
      );
      await settle(tester);
    }

    testWidgets('the detail card lists the purchase source first', (
      tester,
    ) async {
      await pumpShelf(tester, const [
        Spool(
          id: 7,
          material: 'PLA',
          brand: 'Bambu',
          suppliers: [_shop, _extrudr],
        ),
      ]);
      await tester.tap(find.text('Bambu PLA'));
      await settle(tester);
      await scrollSheetDown(tester);

      // The name is the row's title; what was noted about buying there is
      // the line under it, and a supplier with nothing noted has no such line.
      expect(
        find.text(
          '${l10n.inventorySupplierArticleValue('NX2-1')} · '
          '${l10n.inventorySupplierQuotedPrice('24.50')}',
        ),
        findsOneWidget,
      );
      final extrudr = tester.getTopLeft(find.text('Extrudr')).dy;
      final shop = tester.getTopLeft(find.text('Filamentworld')).dy;
      expect(extrudr, lessThan(shop));
      expect(find.text(l10n.inventorySupplierBoughtHere), findsOneWidget);
    });

    testWidgets('the card fits a narrow phone at a large text size', (
      tester,
    ) async {
      usePhoneWindow(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpShelf(tester, const [
        Spool(
          id: 7,
          material: 'PLA',
          brand: 'Bambu',
          costPerKg: 25.99,
          weightUsed: 340,
          storageLocation: 'Shelf A',
          nozzleTempMin: 190,
          nozzleTempMax: 230,
          note: 'Keep it in the dry box after opening, it picks up moisture',
          suppliers: [
            SpoolSupplierLink(
              supplierId: 3,
              supplierName: 'A supplier with a rather long shop name',
              articleNumber: 'GFA00-K0-EXTRA-LONG',
              quotedPricePerKg: 24.99,
              isPurchaseSource: true,
            ),
          ],
        ),
      ]);
      await tester.tap(find.text('Bambu PLA'));
      await settle(tester);
      await scrollSheetDown(tester);

      // An overflow is reported as an exception, which fails the test.
      expect(find.text(l10n.inventorySupplierBoughtHere), findsOneWidget);
      expect(find.text(l10n.inventoryDetailConsumedSinceReset), findsOneWidget);
    });

    testWidgets('every value ends on the same right edge', (tester) async {
      usePhoneWindow(tester);
      await pumpShelf(tester, const [
        Spool(
          id: 7,
          material: 'PLA',
          brand: 'Bambu',
          costPerKg: 25.99,
          weightUsed: 340,
          storageLocation: 'Dry box',
          nozzleTempMin: 190,
          nozzleTempMax: 230,
        ),
      ]);
      await tester.tap(find.text('Bambu PLA'));
      await settle(tester);

      // Labels of different widths; the values must not follow them.
      final edges = {
        for (final value in ['Dry box', '25.99', '190–230 °C'])
          tester.getTopRight(find.text(value)).dx,
      };
      expect(edges, hasLength(1));
    });

    testWidgets('the filter keeps spools that can be bought from a shop', (
      tester,
    ) async {
      await pumpShelf(tester, const [
        Spool(id: 7, material: 'PLA', brand: 'Bambu', suppliers: [_shop]),
        Spool(id: 8, material: 'PETG', brand: 'Bambu', suppliers: []),
      ]);

      await tester.tap(byLogId('inventory.filters'));
      await settle(tester);
      await scrollSheetDown(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Filamentworld'));
      await settle(tester);
      Navigator.of(tester.element(find.byType(FilterChip).first)).pop();
      await settle(tester);

      expect(find.text('Bambu PLA'), findsOneWidget);
      expect(find.text('Bambu PETG'), findsNothing);
    });
  });
}
