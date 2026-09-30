import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'fake_suppliers.dart';

class _Shelf extends InventoryNotifier {
  _Shelf([
    this.spools = const [
      Spool(id: 1, material: 'PLA', brand: 'Bambu', suppliers: []),
    ],
  ]);

  final List<Spool> spools;

  @override
  Future<InventoryState> build() async => InventoryState(spools: spools);
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<void> pumpShelf(
    WidgetTester tester,
    FakeSuppliers suppliers, {
    List<Spool>? spools,
  }) async {
    await pumpPhone(
      tester,
      const InventoryScreen(),
      overrides: [
        inventoryProvider.overrideWith(
          () => spools == null ? _Shelf() : _Shelf(spools),
        ),
        noServerProfileOverride,
        suppliersRepositoryProvider.overrideWithValue(suppliers),
      ],
    );
    await settle(tester);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(byLogId('inventory.suppliers'));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(byLogId('supplier_form.save'));
    await settle(tester);
    await tester.tap(byLogId('supplier_form.save'));
    await settle(tester);
  }

  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

  testWidgets('no entry at all on a server without suppliers', (tester) async {
    await pumpShelf(tester, FakeSuppliers(supported: false));
    expect(byLogId('inventory.suppliers'), findsNothing);
  });

  testWidgets('lists each supplier with what the sheet says about it', (
    tester,
  ) async {
    await pumpShelf(
      tester,
      FakeSuppliers(
        suppliers: const [
          Supplier(
            id: 3,
            name: 'Extrudr',
            website: 'https://extrudr.com',
            customerNumber: 'K-1',
            spoolCount: 2,
          ),
        ],
      ),
    );
    await openSheet(tester);

    expect(find.text('Extrudr'), findsOneWidget);
    expect(
      find.text(
        'https://extrudr.com · ${l10n.inventorySupplierCustomerNumberValue('K-1')}',
      ),
      findsOneWidget,
    );
    // Nothing on the loaded shelf carries it, whatever the server counted.
    expect(find.text(l10n.inventorySpoolCount(0)), findsOneWidget);
  });

  testWidgets('a new supplier is sent trimmed, blanks as null', (tester) async {
    final suppliers = FakeSuppliers();
    await pumpShelf(tester, suppliers);
    await openSheet(tester);
    expect(find.text(l10n.inventorySuppliersEmpty), findsOneWidget);

    await tester.tap(byLogId('suppliers.add'));
    await settle(tester);
    await tester.enterText(
      field('${l10n.inventorySupplierFieldName} *'),
      '  Filament24 ',
    );
    await tester.enterText(
      field(l10n.inventorySupplierFieldCustomerNumber),
      'C-9',
    );
    await save(tester);

    final draft = suppliers.created.single;
    expect(draft.toJson(), {
      'name': 'Filament24',
      'website': null,
      'customer_number': 'C-9',
      'note': null,
    });
    // The sheet under the form reloaded the list.
    expect(find.text('Filament24'), findsOneWidget);
  });

  testWidgets('the separator the CSV export uses is refused before sending', (
    tester,
  ) async {
    final suppliers = FakeSuppliers();
    await pumpShelf(tester, suppliers);
    await openSheet(tester);
    await tester.tap(byLogId('suppliers.add'));
    await settle(tester);

    await tester.enterText(
      field('${l10n.inventorySupplierFieldName} *'),
      'A; B',
    );
    await save(tester);

    expect(find.text(l10n.inventorySupplierNameSeparator), findsOneWidget);
    expect(suppliers.created, isEmpty);
  });

  testWidgets('a taken name says so on the field and keeps the form', (
    tester,
  ) async {
    final suppliers = FakeSuppliers()..failNextWrite = conflict;
    await pumpShelf(tester, suppliers);
    await openSheet(tester);
    await tester.tap(byLogId('suppliers.add'));
    await settle(tester);

    await tester.enterText(
      field('${l10n.inventorySupplierFieldName} *'),
      'Extrudr',
    );
    await save(tester);

    expect(find.text(l10n.inventorySupplierNameTaken), findsOneWidget);
    expect(byLogId('supplier_form.save'), findsOneWidget);

    await tester.enterText(
      field('${l10n.inventorySupplierFieldName} *'),
      'Extrudr DE',
    );
    await tester.pump();
    expect(find.text(l10n.inventorySupplierNameTaken), findsNothing);
  });

  testWidgets('editing sends the row it came from', (tester) async {
    final suppliers = FakeSuppliers(
      suppliers: const [
        Supplier(id: 3, name: 'Extrudr', website: 'https://extrudr.com'),
      ],
    );
    await pumpShelf(tester, suppliers);
    await openSheet(tester);

    await tester.tap(find.text('Extrudr'));
    await settle(tester);
    expect(find.text(l10n.inventorySupplierEdit), findsOneWidget);
    await tester.enterText(field(l10n.inventorySupplierFieldWebsite), '');
    await save(tester);

    final (id, draft) = suppliers.updated.single;
    expect(id, 3);
    expect(draft.website, isNull);
  });

  testWidgets('a refusal is worded with the shelf\'s own count', (
    tester,
  ) async {
    final suppliers = FakeSuppliers(
      suppliers: const [Supplier(id: 3, name: 'Extrudr', spoolCount: 2)],
    )..failNextWrite = conflict;
    await pumpShelf(
      tester,
      suppliers,
      spools: const [
        Spool(
          id: 1,
          material: 'PLA',
          brand: 'Bambu',
          suppliers: [
            SpoolSupplierLink(supplierId: 3, supplierName: 'Extrudr'),
          ],
        ),
      ],
    );
    await openSheet(tester);

    await tester.tap(byLogId('suppliers.delete'));
    await settle(tester);
    // The server decides — the shelf may be stale.
    await tester.tap(byLogId('suppliers.delete_confirm.confirm'));
    await settle(tester);

    expect(find.text(l10n.inventorySupplierInUse(1)), findsOneWidget);
  });

  testWidgets('a count only the server has still reaches the DELETE', (
    tester,
  ) async {
    // A spool deleted in Spoolman itself leaves a row the server counts and
    // prunes only while answering the DELETE — refusing here would make the
    // supplier undeletable.
    final suppliers = FakeSuppliers(
      suppliers: const [Supplier(id: 3, name: 'Extrudr', spoolCount: 1)],
    );
    await pumpShelf(tester, suppliers);
    await openSheet(tester);

    await tester.tap(byLogId('suppliers.delete'));
    await settle(tester);
    await tester.tap(byLogId('suppliers.delete_confirm.confirm'));
    await settle(tester);

    expect(suppliers.deleted, [3]);
  });

  testWidgets('an unused supplier is deleted after confirming', (tester) async {
    final suppliers = FakeSuppliers(
      suppliers: const [Supplier(id: 3, name: 'Extrudr')],
    );
    await pumpShelf(tester, suppliers);
    await openSheet(tester);

    await tester.tap(byLogId('suppliers.delete'));
    await settle(tester);
    await tester.tap(byLogId('suppliers.delete_confirm.confirm'));
    await settle(tester);

    expect(suppliers.deleted, [3]);
    expect(find.text(l10n.inventorySupplierDeleted), findsOneWidget);
    expect(find.text(l10n.inventorySuppliersEmpty), findsOneWidget);
  });

  testWidgets('a 409 on delete means a spool took it since the list loaded', (
    tester,
  ) async {
    final suppliers = FakeSuppliers(
      suppliers: const [Supplier(id: 3, name: 'Extrudr')],
    )..failNextWrite = conflict;
    await pumpShelf(tester, suppliers);
    await openSheet(tester);

    await tester.tap(byLogId('suppliers.delete'));
    await settle(tester);
    await tester.tap(byLogId('suppliers.delete_confirm.confirm'));
    await settle(tester);

    expect(find.text(l10n.inventorySupplierInUseUnknown), findsOneWidget);
  });

  group('the spool count', () {
    const extrudr = SpoolSupplierLink(supplierId: 3, supplierName: 'Extrudr');
    const other = SpoolSupplierLink(supplierId: 5, supplierName: 'Other');

    testWidgets('opens the list narrowed to that supplier', (tester) async {
      await pumpShelf(
        tester,
        FakeSuppliers(
          suppliers: const [Supplier(id: 3, name: 'Extrudr', spoolCount: 2)],
        ),
        spools: const [
          Spool(id: 1, material: 'PLA', brand: 'Bambu', suppliers: [extrudr]),
          Spool(
            id: 2,
            material: 'PETG',
            brand: 'Bambu',
            suppliers: [other, extrudr],
          ),
          Spool(id: 3, material: 'ABS', brand: 'Bambu', suppliers: [other]),
        ],
      );
      await openSheet(tester);

      await tester.tap(byLogId('suppliers.show_spools'));
      await settle(tester);

      expect(byLogId('sheet.suppliers'), findsNothing);
      expect(find.text('Bambu PLA'), findsOneWidget);
      expect(find.text('Bambu PETG'), findsOneWidget);
      expect(find.text('Bambu ABS'), findsNothing);
    });

    testWidgets('counts active and archived apart, each opening its own', (
      tester,
    ) async {
      await pumpShelf(
        tester,
        // The server's count includes the archived spool: 2, not 1.
        FakeSuppliers(
          suppliers: const [Supplier(id: 3, name: 'Extrudr', spoolCount: 2)],
        ),
        spools: const [
          Spool(
            id: 1,
            material: 'PLA',
            brand: 'Bambu',
            archivedAt: '2026-09-01T00:00:00Z',
            suppliers: [extrudr],
          ),
          Spool(id: 2, material: 'PETG', brand: 'Bambu', suppliers: [extrudr]),
          Spool(id: 3, material: 'ABS', brand: 'Bambu', suppliers: [other]),
        ],
      );
      await openSheet(tester);
      expect(find.text(l10n.inventorySpoolCount(1)), findsOneWidget);
      expect(find.text(l10n.inventorySupplierArchivedCount(1)), findsOneWidget);

      await tester.tap(byLogId('suppliers.show_archived_spools'));
      await settle(tester);

      expect(find.text('Bambu PLA'), findsOneWidget);
      expect(find.text('Bambu PETG'), findsNothing);
      expect(find.text('Bambu ABS'), findsNothing);
    });

    testWidgets('clears a search that would hide them', (tester) async {
      await pumpShelf(
        tester,
        FakeSuppliers(
          suppliers: const [Supplier(id: 3, name: 'Extrudr', spoolCount: 1)],
        ),
        spools: const [
          Spool(id: 1, material: 'PETG', brand: 'Bambu', suppliers: [extrudr]),
          Spool(id: 2, material: 'ABS', brand: 'Bambu', suppliers: [other]),
        ],
      );
      await tester.enterText(byLogId('inventory.search'), 'ABS');
      await settle(tester);
      expect(find.text('Bambu PETG'), findsNothing);

      await openSheet(tester);
      await tester.tap(byLogId('suppliers.show_spools'));
      await settle(tester);

      expect(find.text('Bambu PETG'), findsOneWidget);
      expect(find.text('ABS'), findsNothing);
    });

    testWidgets('finds spools whose links still carry an old name', (
      tester,
    ) async {
      // Right after a rename the shelf has not reloaded yet.
      await pumpShelf(
        tester,
        FakeSuppliers(
          suppliers: const [Supplier(id: 3, name: 'Extrudr DE', spoolCount: 1)],
        ),
        spools: const [
          Spool(id: 1, material: 'PETG', brand: 'Bambu', suppliers: [extrudr]),
        ],
      );
      await openSheet(tester);
      await tester.tap(byLogId('suppliers.show_spools'));
      await settle(tester);

      expect(find.text('Bambu PETG'), findsOneWidget);
    });

    testWidgets('is plain text when nothing is assigned', (tester) async {
      await pumpShelf(
        tester,
        FakeSuppliers(suppliers: const [Supplier(id: 3, name: 'Extrudr')]),
      );
      await openSheet(tester);

      expect(byLogId('suppliers.show_spools'), findsNothing);
      expect(find.text(l10n.inventorySpoolCount(0)), findsOneWidget);
    });
  });
}
