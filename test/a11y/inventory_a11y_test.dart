import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/demo/demo_label_printer.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/core/settings/label_print_prefs.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets of the Filaments tab, both backends. The
/// native shelf runs over the demo server; the Spoolman shelf is a fixed list
/// under `inventoryBackendOverride`, because the demo answers no
/// `/spoolman/inventory` route. Covered: the list and its filter, empty, error
/// and no-match states; selection mode with the bulk menu, each bulk
/// confirmation and the mass-edit sheet (pickers, errors, confirmation); the
/// labels flow step by step; the climate and suppliers sheets with their forms;
/// the detail sheet in each state, its confirmations and the assign sheet; the
/// spool form in every state it has, with each picker it opens. Each long sheet
/// has a scrolled variant, since the harness scrolls the screen behind a sheet,
/// not the sheet. Deliberately not covered: the QR scanner (a camera platform
/// view, which a widget test cannot show), and the system share, print and save
/// hand-offs that follow a label print.
void main() {
  // The demo is process-wide and these surfaces write to it.

  // --- List ---

  a11ySurface(
    'inventory',
    home: () => const InventoryScreen(),
    shows: find.text(_gold),
  );

  a11ySurface(
    'inventory, archived',
    overrides: [_archivedFilter],
    home: () => const InventoryScreen(),
    shows: find.text(_archivedSpool),
  );

  a11ySurface(
    'inventory, search without a match',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.enterText(byLogId('inventory.search'), 'zzzz');
    },
    shows: find.text(pl.inventoryNoMatches),
  );

  a11ySurface(
    'inventory, empty shelf',
    overrides: [_shelfOverride(const [])],
    home: () => const InventoryScreen(),
    shows: find.text(pl.inventoryEmpty),
  );

  a11ySurface(
    'inventory, list failed',
    overrides: [_failingShelf],
    home: () => const InventoryScreen(),
    shows: find.text(pl.retry),
  );

  // --- Filters ---

  a11ySurface(
    'inventory, filter sheet',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('inventory.filters'));
    },
    shows: byLogId('sheet.inventory_filters'),
  );

  a11ySurface(
    'inventory, filter sheet scrolled',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('inventory.filters'));
      await settle(tester);
      await scrollSheetDown(tester);
    },
    shows: byLogId('sheet.inventory_filters'),
  );

  a11ySurface(
    'inventory, filter sheet with a sort and chips picked',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('inventory.filters'));
      await settle(tester);
      await tester.tap(find.text(pl.inventorySortUsage));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'PETG'));
      await tester.tap(find.widgetWithText(FilterChip, 'Dry box'));
    },
    shows: byLogId('inventory.filters_clear'),
  );

  a11ySurface(
    'inventory, filters leave nothing',
    overrides: [
      _lowStockOnlyFilter,
      _shelfOverride(const [_plainSpool]),
    ],
    home: () => const InventoryScreen(),
    shows: find.text(pl.inventoryNoMatches),
  );

  // --- Climate and suppliers ---

  a11ySurface(
    'inventory, climate sheet',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('inventory.location_climate'));
    },
    shows: byLogId('sheet.location_climate'),
  );

  a11ySurface(
    'inventory, suppliers sheet',
    home: () => const InventoryScreen(),
    arrange: _openSuppliers,
    shows: find.text('Filament24'),
  );

  a11ySurface(
    'inventory, suppliers sheet without suppliers',
    overrides: [supplierListProvider.overrideWith((ref) async => const [])],
    home: () => const InventoryScreen(),
    arrange: _openSuppliers,
    shows: find.text(pl.inventorySuppliersEmpty),
  );

  a11ySurface(
    'inventory, suppliers sheet failed',
    overrides: [
      supplierListProvider.overrideWith(
        (ref) async => throw const ApiException(AppErrorCode.connectionError),
      ),
    ],
    home: () => const InventoryScreen(),
    arrange: _openSuppliers,
    shows: find.text(pl.inventorySuppliersLoadFailed),
  );

  a11ySurface(
    'inventory, supplier form',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openSuppliers(tester);
      await tester.tap(byLogId('suppliers.add'));
    },
    shows: find.text(pl.inventorySupplierNew),
  );

  a11ySurface(
    'inventory, supplier form of an existing supplier',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openSuppliers(tester);
      await tester.tap(byLogId('suppliers.edit').first);
    },
    shows: find.text(pl.inventorySupplierEdit),
  );

  a11ySurface(
    'inventory, supplier form with an empty name',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openSuppliers(tester);
      await tester.tap(byLogId('suppliers.add'));
      await settle(tester);
      await tester.tap(byLogId('supplier_form.save'));
    },
    shows: find.text(pl.inventoryFieldRequired),
  );

  a11ySurface(
    'inventory, supplier form with a name already taken',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openSuppliers(tester);
      await tester.tap(byLogId('suppliers.add'));
      await settle(tester);
      await tester.enterText(_input('supplier_form.name'), 'Filament24');
      await tester.tap(byLogId('supplier_form.save'));
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: find.text(pl.inventorySupplierNameTaken),
  );

  a11ySurface(
    'inventory, supplier delete confirmation',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openSuppliers(tester);
      await tester.tap(byLogId('suppliers.delete').first);
    },
    shows: byLogId('suppliers.delete_confirm.confirm'),
  );

  // --- Selection and bulk actions ---

  a11ySurface(
    'inventory, selection mode',
    home: () => const InventoryScreen(),
    arrange: _select,
    shows: byLogId('inventory.select_all'),
  );

  a11ySurface(
    'inventory, bulk menu',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _select(tester);
      await tester.tap(byLogId('inventory.bulk_menu'));
    },
    shows: find.text(pl.inventoryBulkEdit),
  );

  a11ySurface(
    'inventory, bulk menu of archived spools',
    overrides: [_archivedFilter],
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _select(tester, _archivedSpool);
      await tester.tap(byLogId('inventory.bulk_menu'));
    },
    shows: find.text(pl.inventoryRestore),
  );

  for (final (name, menuItem, title) in [
    ('reset usage', pl.inventoryResetUsage, pl.inventoryBulkResetTitle(1)),
    ('archive', pl.inventoryArchive, pl.inventoryBulkArchiveTitle(1)),
    ('delete', pl.inventoryDelete, pl.inventoryBulkDeleteTitle(1)),
  ]) {
    a11ySurface(
      'inventory, bulk $name confirmation',
      home: () => const InventoryScreen(),
      arrange: (tester) async {
        await _select(tester);
        await tester.tap(byLogId('inventory.bulk_menu'));
        await settle(tester);
        await tester.tap(find.text(menuItem));
      },
      shows: find.text(title),
    );
  }

  a11ySurface(
    'inventory, bulk restore confirmation',
    overrides: [_archivedFilter],
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _select(tester, _archivedSpool);
      await tester.tap(byLogId('inventory.bulk_menu'));
      await settle(tester);
      await tester.tap(find.text(pl.inventoryRestore));
    },
    shows: find.text(pl.inventoryBulkRestoreTitle(1)),
  );

  // --- Mass edit ---

  a11ySurface(
    'inventory, mass edit sheet',
    home: () => const InventoryScreen(),
    arrange: _openBulkEdit,
    shows: find.text(pl.inventoryBulkEditTitle(1)),
  );

  a11ySurface(
    'inventory, mass edit sheet scrolled',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openBulkEdit(tester);
      await scrollSheetDown(tester);
    },
    shows: byLogId('bulk_edit.apply'),
  );

  a11ySurface(
    'inventory, mass edit sheet with its errors',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openBulkEdit(tester);
      await tester.enterText(_input('bulk_edit.cost_per_kg'), 'abc');
      await tester.enterText(_input('bulk_edit.low_stock'), '100');
      await scrollSheetDown(tester);
      await tester.tap(byLogId('bulk_edit.apply'));
      await settle(tester);
    },
    shows: find.text(pl.inventoryFieldInvalidNumber),
  );

  a11ySurface(
    'inventory, mass edit confirmation',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openBulkEdit(tester);
      await tester.enterText(_input('bulk_edit.note'), 'Moved to the shelf');
      await scrollSheetDown(tester);
      await tester.tap(byLogId('bulk_edit.apply'));
    },
    shows: find.text(pl.inventoryBulkEditConfirmTitle(1)),
  );

  a11ySurface(
    'inventory, mass edit slicer preset picker',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openBulkEdit(tester);
      await tester.tap(byLogId('bulk_edit.preset'));
    },
    shows: byLogId('spool_form.preset_search'),
  );

  a11ySurface(
    'inventory, mass edit colour dialog',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openBulkEdit(tester);
      await tester.tap(byLogId('bulk_edit.color'));
    },
    shows: byLogId('bulk_edit_color.confirm'),
  );

  a11ySurface(
    'inventory, mass edit sheet with a supplier added',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openBulkEdit(tester);
      await scrollSheetDown(tester);
      await tester.tap(byLogId('bulk_edit.supplier_add'));
      await settle(tester);
      await tester.tap(byLogId('supplier_picker.option').first);
      await settle(tester);
      await scrollSheetDown(tester);
    },
    shows: byLogId('bulk_edit.supplier_remove'),
  );

  // --- Labels ---

  a11ySurface(
    'inventory, labels sheet',
    home: () => const InventoryScreen(),
    arrange: _openLabels,
    shows: byLogId('spool_labels.search'),
  );

  a11ySurface(
    'inventory, labels sheet with nothing picked',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openLabels(tester);
      await tester.tap(find.text(pl.inventoryLabelsClearAll));
    },
    shows: find.text(pl.inventorySelectedCount(0)),
  );

  a11ySurface(
    'inventory, labels sheet without a match',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openLabels(tester);
      await tester.enterText(byLogId('spool_labels.search'), 'zzzz');
    },
    shows: find.text(pl.inventoryLabelsNoMatches),
  );

  a11ySurface(
    'inventory, labels sheet material menu',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openLabels(tester);
      await tester.tap(byLogId('spool_labels.material'));
    },
    shows: byLogId('spool_labels.material.option'),
  );

  a11ySurface(
    'inventory, label template sheet',
    home: () => const InventoryScreen(),
    arrange: _openLabelTemplates,
    shows: find.text(pl.inventoryLabelsPickTemplate),
  );

  a11ySurface(
    'inventory, label starting position sheet',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openLabelTemplates(tester);
      await tester.tap(find.text(pl.inventoryLabelsAveryL7160));
    },
    shows: find.text(pl.inventoryLabelsStartTitle),
  );

  a11ySurface(
    'inventory, label options sheet',
    home: () => const InventoryScreen(),
    arrange: _openLabelOptions,
    shows: find.text(pl.labelOptionsTitle),
  );

  a11ySurface(
    'inventory, label options sheet scrolled',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openLabelOptions(tester);
      await scrollSheetDown(tester);
    },
    shows: byLogId('label_options.destination'),
  );

  a11ySurface(
    'inventory, label options sheet for PNG',
    overrides: [_pngPrefs],
    home: () => const InventoryScreen(),
    arrange: _openLabelOptions,
    shows: byLogId('label_options.dpi'),
  );

  a11ySurface(
    'inventory, label options sheet with a label printer set up',
    overrides: [_labelPrinterChosen],
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openLabelOptions(tester);
      await scrollSheetDown(tester);
    },
    shows: byLogId('label_options.cut_at_end'),
  );

  // --- Detail sheet ---

  a11ySurface(
    'inventory, detail sheet of an unassigned spool',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_loose));
    },
    shows: byLogId('spool_actions.assign'),
  );

  a11ySurface(
    'inventory, detail sheet of a loaded spool',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_black).first);
    },
    shows: byLogId('spool_actions.unassign'),
  );

  a11ySurface(
    'inventory, detail sheet of a loaded spool scrolled',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_black).first);
      await settle(tester);
      await scrollSheetDown(tester);
    },
    shows: find.text(pl.inventoryUsageHistory),
  );

  a11ySurface(
    'inventory, detail sheet of an archived spool',
    overrides: [_archivedFilter],
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_archivedSpool));
    },
    shows: byLogId('spool_actions.restore'),
  );

  a11ySurface(
    'inventory, detail sheet with the climate of its shelf',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_petg));
      await settle(tester);
      await scrollSheetDown(tester);
    },
    shows: find.byIcon(Icons.water_drop_outlined),
  );

  a11ySurface(
    'inventory, detail sheet of a low spool with every field',
    overrides: [
      _shelfOverride([_fullSpool]),
    ],
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_fullSpool.displayName));
      await settle(tester);
      await scrollSheetDown(tester);
    },
    shows: find.text(pl.inventoryKProfiles),
  );

  a11ySurface(
    'inventory, detail sheet without a readable usage history',
    overrides: [
      spoolUsageProvider.overrideWith(
        (ref, id) async =>
            throw const ApiException(AppErrorCode.connectionError),
      ),
    ],
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_black).first);
      await settle(tester);
      await scrollSheetDown(tester);
    },
    shows: find.text(pl.inventoryUsageEmpty),
  );

  a11ySurface(
    'inventory, reset usage confirmation',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_gold));
      await settle(tester);
      await tester.tap(byLogId('spool_actions.reset_usage'));
    },
    shows: find.text(pl.inventoryResetUsageConfirm),
  );

  a11ySurface(
    'inventory, delete confirmation',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_gold));
      await settle(tester);
      await tester.tap(byLogId('spool_actions.delete'));
    },
    shows: find.text(pl.inventoryDeleteTitle),
  );

  // --- Assign sheet ---

  a11ySurface(
    'inventory, assign sheet',
    home: () => const InventoryScreen(),
    arrange: _openAssign,
    shows: find.text(pl.inventoryAssignTitle),
  );

  a11ySurface(
    'inventory, assign sheet to an external spool holder',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openAssign(tester);
      await tester.tap(find.text(pl.externalSpool));
    },
    shows: find.text(pl.inventoryAssignExternalHint),
  );

  a11ySurface(
    'inventory, assign sheet printer menu',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openAssign(tester);
      await tester.tap(byLogId('spool_assign.printer'));
    },
    shows: byLogId('spool_assign.printer_option'),
  );

  a11ySurface(
    'inventory, assign sheet unit menu',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openAssign(tester);
      await tester.tap(byLogId('spool_assign.unit'));
    },
    shows: byLogId('spool_assign.unit.0'),
  );

  a11ySurface(
    'inventory, assign sheet to a dual-nozzle printer',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openAssign(tester);
      await tester.tap(byLogId('spool_assign.printer'));
      await settle(tester);
      await tester.tap(find.text('H2D').last);
      await settle(tester);
      await tester.tap(find.text(pl.externalSpool));
    },
    shows: byLogId('spool_assign.extruder'),
  );

  a11ySurface(
    'inventory, assign sheet without printers',
    overrides: [fixedDashboardOverride()],
    home: () => const InventoryScreen(),
    arrange: _openAssign,
    shows: find.text(pl.inventoryAssignNoPrinters),
  );

  // --- Spool form, native backend ---

  a11ySurface(
    'inventory, new spool form',
    home: () => const InventoryScreen(),
    arrange: _openNewSpool,
    shows: find.text(pl.inventoryNewSpool),
  );

  a11ySurface(
    'inventory, new spool form scrolled',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await scrollSheetDown(tester, times: 6);
    },
    shows: byLogId('spool_form.cost_per_kg'),
  );

  a11ySurface(
    'inventory, new spool form scrolled to its end',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await scrollSheetDown(tester, times: 16);
    },
    shows: byLogId('spool_form.save'),
  );

  a11ySurface(
    'inventory, new spool form with its errors',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await tester.enterText(_input('spool_form.label_weight'), 'abc');
      await tester.enterText(_input('spool_form.cost_per_kg'), '-3');
      await scrollSheetDown(tester);
      await a11yTap(tester, byLogId('spool_form.save'));
      await settle(tester);
    },
    shows: find.text(pl.inventoryFieldRequired),
  );

  a11ySurface(
    'inventory, new spool form for several spools',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await a11yTap(tester, find.byTooltip(pl.inventoryQuantityMore));
    },
    shows: find.text(pl.inventoryAddSpools(2)),
  );

  a11ySurface(
    'inventory, new spool form material menu',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await tester.tap(byLogId('spool_form.material'));
    },
    shows: find.byType(MenuItemButton),
    // The scrolling pass jumps the form while the menu hangs off a field in it;
    // once the field is out of the list the menu's anchor is gone and Flutter lays
    // the overlay out at NaN. A finger cannot do that: the menu's barrier takes the
    // first drag and only closes the menu.
    scroll: false,
  );

  a11ySurface(
    'inventory, new spool form effect menu',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await scrollSheetDown(tester, times: 2);
      await tester.tap(byLogId('spool_form.effect'));
    },
    shows: byLogId('spool_form.effect.none'),
  );

  a11ySurface(
    'inventory, new spool form with a catalogue colour picked',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await tester.tap(byLogId('spool_form.color_swatch').first);
    },
    shows: byLogId('spool_form.color_swatch'),
  );

  a11ySurface(
    'inventory, colour dialog',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await tester.tap(byLogId('spool_form.color'));
    },
    shows: byLogId('spool_color.confirm'),
  );

  a11ySurface(
    'inventory, empty spool weight picker',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await scrollSheetDown(tester, times: 2);
      await tester.tap(byLogId('spool_form.core_weight'));
    },
    shows: byLogId('spool_form.core_search'),
  );

  a11ySurface(
    'inventory, slicer preset picker',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await tester.tap(byLogId('spool_form.preset'));
    },
    shows: byLogId('spool_form.preset_search'),
  );

  a11ySurface(
    'inventory, slicer preset picker narrowed by the material',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openNewSpool(tester);
      await tester.enterText(_input('spool_form.material'), 'PLA');
      await tester.tap(byLogId('spool_form.preset'));
    },
    shows: byLogId('spool_form.preset_filter_material'),
  );

  // --- Spool form, editing ---

  a11ySurface(
    'inventory, edit spool form',
    home: () => const InventoryScreen(),
    arrange: _openEditOfBlack,
    shows: find.text(pl.inventoryEditSpool),
  );

  a11ySurface(
    'inventory, edit spool form scrolled',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openEditOfBlack(tester);
      await scrollSheetDown(tester, times: 6);
    },
    shows: byLogId('spool_form.cost_per_kg'),
  );

  a11ySurface(
    'inventory, edit spool form scrolled to its end',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openEditOfBlack(tester);
      await scrollSheetDown(tester, times: 16);
    },
    shows: byLogId('spool_form.save'),
  );

  a11ySurface(
    'inventory, duplicate spool form',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_black).first);
      await settle(tester);
      await tester.tap(byLogId('spool_actions.duplicate'));
    },
    shows: find.text(pl.inventoryNewSpool),
  );

  a11ySurface(
    'inventory, printer preset picker',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openEditOfBlack(tester);
      await scrollSheetDown(tester, times: 8);
      await tester.tap(byLogId('spool_form.model_preset').first);
    },
    shows: byLogId('spool_form.preset_filter_model'),
  );

  a11ySurface(
    'inventory, supplier picker',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openEditOfBlack(tester);
      await scrollSheetDown(tester, times: 16);
      await tester.tap(byLogId('spool_form.supplier_add'));
    },
    shows: byLogId('sheet.supplier_picker'),
  );

  a11ySurface(
    'inventory, supplier picker with every supplier taken',
    overrides: [
      supplierListProvider.overrideWith(
        (ref) async => const [Supplier(id: 1, name: 'Bambu Lab Store')],
      ),
    ],
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openEditOfBlack(tester);
      await scrollSheetDown(tester, times: 16);
      await tester.tap(byLogId('spool_form.supplier_add'));
    },
    shows: find.text(pl.inventorySupplierNoneLeft),
  );

  a11ySurface(
    'inventory, last dried date dialog',
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _openEditOfBlack(tester);
      await scrollSheetDown(tester, times: 8);
      await tester.tap(byLogId('spool_form.last_dried'));
    },
    shows: find.byType(Dialog),
  );

  // --- Spoolman backend ---

  a11ySurface(
    'inventory, Spoolman shelf',
    overrides: _spoolman,
    home: () => const InventoryScreen(),
    shows: find.text(_fullSpool.displayName),
  );

  a11ySurface(
    'inventory, Spoolman filter sheet',
    overrides: _spoolman,
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('inventory.filters'));
    },
    shows: byLogId('sheet.inventory_filters'),
  );

  a11ySurface(
    'inventory, Spoolman mass edit sheet',
    overrides: _spoolman,
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await _select(tester, _fullSpool.displayName);
      await tester.tap(byLogId('inventory.bulk_menu'));
      await settle(tester);
      await tester.tap(find.text(pl.inventoryBulkEdit));
    },
    shows: find.text(pl.inventoryBulkEditTitle(1)),
  );

  a11ySurface(
    'inventory, Spoolman edit spool form',
    overrides: _spoolman,
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_fullSpool.displayName));
      await settle(tester);
      await tester.tap(byLogId('spool_actions.edit'));
    },
    shows: find.text(pl.inventoryEditSpool),
  );

  a11ySurface(
    'inventory, Spoolman edit spool form with a brand it cannot clear',
    overrides: _spoolman,
    home: () => const InventoryScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_fullSpool.displayName));
      await settle(tester);
      await tester.tap(byLogId('spool_actions.edit'));
      await settle(tester);
      await tester.enterText(_input('spool_form.brand'), '');
      await tester.pump();
    },
    shows: find.text(pl.inventorySpoolmanCannotClear),
  );
}

// --- Navigation helpers ---

/// Loaded in a slot, with a counter that was reset once.
const _gold = 'Bambu Lab PLA Silk';

/// The shelf's unassigned spool, so the assign pill is on its card.
const _loose = 'Bambu Lab TPU 95A';
const _black = 'Bambu Lab PLA Basic';
const _petg = 'Bambu Lab PETG HF';
const _archivedSpool = 'Bambu Lab ABS';

/// A text field's editable, from the diagnostic id the field is tagged with.
Finder _input(String id) =>
    find.descendant(of: byLogId(id), matching: find.byType(TextField));

/// Long-presses a tile, which is how selection mode starts.
Future<void> _select(WidgetTester tester, [String name = _gold]) async {
  await tester.longPress(find.text(name).first);
  await settle(tester);
}

Future<void> _openSuppliers(WidgetTester tester) async {
  await tester.tap(byLogId('inventory.suppliers'));
  await settle(tester);
}

Future<void> _openBulkEdit(WidgetTester tester) async {
  await _select(tester);
  await tester.tap(byLogId('inventory.bulk_menu'));
  await settle(tester);
  await tester.tap(find.text(pl.inventoryBulkEdit));
  await settle(tester);
}

Future<void> _openLabels(WidgetTester tester) async {
  await tester.tap(byLogId('inventory.print_labels_all'));
  await settle(tester);
}

Future<void> _openLabelTemplates(WidgetTester tester) async {
  await _openLabels(tester);
  await tester.tap(byLogId('labels.print'));
  await settle(tester);
}

Future<void> _openLabelOptions(WidgetTester tester) async {
  await _openLabelTemplates(tester);
  await tester.tap(find.text(pl.inventoryLabelsBox62));
  await a11ySettle(tester, const Duration(seconds: 1));
}

Future<void> _openAssign(WidgetTester tester) async {
  await tester.tap(find.text(_loose));
  await settle(tester);
  await tester.tap(byLogId('spool_actions.assign'));
  await settle(tester);
}

Future<void> _openNewSpool(WidgetTester tester) async {
  await tester.tap(byLogId('inventory.add_spool'));
  await settle(tester);
}

Future<void> _openEditOfBlack(WidgetTester tester) async {
  await tester.tap(find.text(_black).first);
  await settle(tester);
  await tester.tap(byLogId('spool_actions.edit'));
  await settle(tester);
}

// --- Fixtures ---

final _archivedFilter = inventoryFiltersProvider.overrideWith(
  (ref) => const InventoryFilters(showArchived: true),
);

final _lowStockOnlyFilter = inventoryFiltersProvider.overrideWith(
  (ref) => const InventoryFilters(lowStockOnly: true),
);

/// What a fixed shelf serves, for the states the demo cannot be put in.
class _Shelf extends InventoryNotifier {
  _Shelf(this._spools);

  final List<Spool> _spools;

  @override
  Future<InventoryState> build() async => InventoryState(spools: _spools);

  @override
  Future<void> refresh({bool askBackend = false}) async {}
}

Override _shelfOverride(List<Spool> spools) =>
    inventoryProvider.overrideWith(() => _Shelf(spools));

class _FailingShelf extends InventoryNotifier {
  @override
  Future<InventoryState> build() async =>
      throw const ApiException(AppErrorCode.connectionError);
}

final _failingShelf = inventoryProvider.overrideWith(_FailingShelf.new);

/// A spool with nothing the low-stock filter keeps.
const _plainSpool = Spool(
  id: 1,
  material: 'PLA',
  brand: 'Bambu Lab',
  labelWeight: 1000,
);

/// Every line the detail sheet can show, at a weight that makes it low.
final _fullSpool = Spool(
  id: 40,
  material: 'PETG',
  subtype: 'HF',
  brand: 'Polymaker',
  colorName: 'Teal',
  rgba: '0ACCB8FF',
  labelWeight: 1000,
  weightUsed: 930,
  weightUsedBaseline: 100,
  costPerKg: 29.99,
  lowStockThresholdPct: 20,
  storageLocation: 'Dry box',
  category: 'Engineering',
  note: 'Opened, keep it dry between prints',
  nozzleTempMin: 230,
  nozzleTempMax: 260,
  tagUid: '0123456789ABCDEF',
  slicerFilamentName: 'Polymaker PETG HF',
  materialNumber: 'A-104',
  lastDriedAt: DateTime(2026, 10, 20, 8, 30),
  lastDriedTemp: 65,
  lastDriedHours: 6,
  kProfiles: const [
    SpoolKProfile(
      id: 1,
      name: 'Textured plate',
      kValue: 0.032,
      nozzleDiameter: '0.4',
    ),
  ],
  suppliers: const [
    SpoolSupplierLink(
      supplierId: 1,
      supplierName: 'Bambu Lab Store',
      articleNumber: 'GFG00-K0',
      quotedPricePerKg: 24.99,
      isPurchaseSource: true,
    ),
  ],
);

final _spoolman = [
  _shelfOverride([_fullSpool, _plainSpool]),
  inventoryBackendOverride(InventoryBackend.spoolman),
  inventoryRepositoryOf(InventoryBackend.spoolman),
];

class _PngPrefsNotifier extends LabelPrintPrefsNotifier {
  @override
  LabelPrintPrefs build() =>
      const LabelPrintPrefs(format: SpoolLabelFormat.png);

  @override
  Future<void> set(LabelPrintPrefs prefs) async => state = prefs;
}

final _pngPrefs = labelPrintPrefsProvider.overrideWith(_PngPrefsNotifier.new);

class _DemoLabelPrinterUrl extends LabelPrinterUrlNotifier {
  @override
  String? build() => demoLabelPrinterUrl;
}

/// The demo's label print server, which answers `/info` in process and takes
/// the 62x29 stock the label sheet offers.
final _labelPrinterChosen = labelPrinterUrlProvider.overrideWith(
  _DemoLabelPrinterUrl.new,
);
