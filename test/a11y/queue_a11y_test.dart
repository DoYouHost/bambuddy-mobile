import 'dart:async';

import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_bulk_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/features/queue/queue_history.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/queue/queue_form_harness.dart';
import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the queue: the list with its resume
/// banners, selection mode, the card menu and the dialogs and sheets it opens,
/// the History tab with its sort menu and confirmations, the bulk edit, and
/// the print form in every state it has. The harness and the rules are in
/// a11y_harness.dart. Not covered: the G-code preview a card menu opens (a
/// platform-rendered viewer, `lib/features/gcode`, covered with that feature).

/// A demo pending job as the queue lists it, for a screen that is handed an
/// item. Library file 5 is the demo's sliced Gridfinity bin.
QueueItem _demoItem({
  int id = 101,
  int? printerId = 1,
  String? targetModel,
  int libraryFileId = 5,
  String slicedForModel = 'X1C',
  bool gcodeInjection = false,
  String filamentType = 'PETG',
  String filamentColor = '#FFFFFF',
  int? costCenterId = 1,
}) => QueueItem.fromJson({
  'id': id,
  'position': id,
  'status': 'pending',
  'printer_id': printerId,
  'target_model': targetModel,
  'library_file_id': libraryFileId,
  'library_file_name': 'Gridfinity bin 2×1×9',
  'filament_type': filamentType,
  'filament_color': filamentColor,
  'sliced_for_model': slicedForModel,
  'gcode_injection': gcodeInjection,
  'cost_center_id': costCenterId,
  'print_time_seconds': 5520,
  'filament_used_grams': 42.3,
});

/// A printer whose finished job still sits on the plate.
class _DirtyPlateStatuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {
    1: PrinterStatus(id: 1, connected: true, awaitingPlateClear: true),
  };
}

class _FailingQueue extends QueueNotifier {
  @override
  Future<List<QueueItem>> build() async => throw StateError('unreachable');
}

class _EmptyQueue extends QueueNotifier {
  @override
  Future<List<QueueItem>> build() async => const [];
}

/// A History tab answering [state] instead of the demo's server.
class _History extends QueueHistoryNotifier {
  _History(this._state);

  final Future<QueueHistoryState> Function() _state;

  @override
  Future<QueueHistoryState> build() => _state();

  @override
  Future<void> refresh() async {}
}

QueueItem _done(
  int id, {
  int? batchId,
  String status = 'completed',
  String? error,
  List<Map<String, dynamic>>? substitutions,
}) => QueueItem.fromJson({
  'id': id,
  'position': id,
  'status': status,
  'archive_id': 100 + id,
  'archive_name': 'Part $id',
  'printer_name': 'X1C-01',
  'batch_id': batchId,
  'batch_name': batchId == null ? null : 'Keychains ×6',
  'error_message': error,
  'color_substitutions': substitutions,
  'filament_type': 'PLA',
  'filament_color': '#1F8F4D',
  'filament_used_grams': 12.4,
  'print_time_seconds': 2760,
  'created_by_username': 'admin',
  'completed_at': '2026-10-20T10:00:00',
});

Override _historyOverride(Future<QueueHistoryState> Function() state) =>
    queueHistoryProvider.overrideWith(() => _History(state));

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(byLogId('queue.tab_history'));
  await tester.pumpAndSettle();
}

Future<void> _longPressFirstCard(WidgetTester tester) async {
  await tester.longPress(find.text('Gridfinity bin 2×1×9'));
  await tester.pumpAndSettle();
}

Future<void> main() async {
  // The shared print-form rig reads its remembered options from these.
  await setUpQueueForm();

  // --- The queue tab ---

  a11ySurface(
    'queue',
    home: () => const QueueScreen(),
    shows: find.text(pl.queueStartNext),
  );

  a11ySurface(
    'queue, empty',
    demo: false,
    overrides: [
      noServerProfileOverride,
      queueProvider.overrideWith(_EmptyQueue.new),
    ],
    home: () => const QueueScreen(),
    shows: find.text(pl.queueEmpty),
  );

  a11ySurface(
    'queue, load failed',
    overrides: [queueProvider.overrideWith(_FailingQueue.new)],
    home: () => const QueueScreen(),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'queue, one card picked',
    home: () => const QueueScreen(),
    arrange: _longPressFirstCard,
    shows: find.text(pl.queueSelectedCount(1)),
  );

  a11ySurface(
    'queue, every card picked',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await _longPressFirstCard(tester);
      await tester.tap(byLogId('queue.select_all'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue.bulk_edit'),
  );

  // The demo's printing card is pinned first, the waiting cards follow in
  // queue order: one with a printer, then one without.
  a11ySurface(
    'queue, menu of the printing card',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.actions').first);
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue.action.cancel'),
  );

  a11ySurface(
    'queue, menu of a waiting card',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.actions').at(1));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueEdit),
  );

  a11ySurface(
    'queue, stop confirmation',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.actions').first);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue.action.cancel'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueStopTitle),
  );

  a11ySurface(
    'queue, swipe-to-delete confirmation',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.fling(
        find.text('Gridfinity bin 2×1×9'),
        const Offset(-600, 0),
        2000,
      );
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueDeleteTitle),
  );

  a11ySurface(
    'queue, start next opens the filament mapping',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.start_next'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue_mapping.confirm'),
  );

  a11ySurface(
    'queue, plate-clear confirmation of the start flow',
    overrides: [
      requirePlateClearProvider.overrideWithValue(const AsyncData(true)),
      printerStatusesProvider.overrideWith(_DirtyPlateStatuses.new),
    ],
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.start_next'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue_mapping.confirm'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.plateClearTitle),
  );

  a11ySurface(
    'queue, printer picker of the start flow',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.actions').at(2));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue.action.start'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.pickPrinterTitle),
  );

  a11ySurface(
    'queue, resume banner confirmation',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.resume').first);
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueResumeConfirmTitle),
  );

  // --- The History tab ---

  a11ySurface(
    'queue history',
    home: () => const QueueScreen(),
    arrange: _openHistory,
    shows: find.text(pl.queueHistoryClear),
  );

  a11ySurface(
    'queue history, empty',
    overrides: [
      _historyOverride(
        () async => (
          items: const <QueueItem>[],
          total: 0,
          serverOrdered: true,
          limit: 50,
        ),
      ),
    ],
    home: () => const QueueScreen(),
    arrange: _openHistory,
    shows: find.text(pl.queueHistoryEmpty),
  );

  a11ySurface(
    'queue history, load failed',
    overrides: [_historyOverride(() async => throw StateError('unreachable'))],
    home: () => const QueueScreen(),
    arrange: _openHistory,
    shows: find.text(pl.retry),
  );

  // A batch folded into one row, a failed run with its reason, and the
  // "show more" footer (more rows on the server than the page holds).
  final batched = (
    items: [
      _done(1, batchId: 4),
      _done(2, batchId: 4, status: 'failed', error: 'Filament ran out'),
      // A chip for a slot printed in another colour: its tap target and ink.
      _done(
        3,
        substitutions: const [
          {'slot_id': 1, 'type': 'PLA', 'wanted': '#FF0000', 'got': '#00FF00'},
        ],
      ),
      _done(4, status: 'cancelled'),
    ],
    total: 120,
    serverOrdered: true,
    limit: 50,
  );

  a11ySurface(
    'queue history, batch folded with show more',
    overrides: [_historyOverride(() async => batched)],
    home: () => const QueueScreen(),
    arrange: _openHistory,
    shows: byLogId('queue_history.show_more'),
  );

  a11ySurface(
    'queue history, batch unfolded',
    overrides: [_historyOverride(() async => batched)],
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await _openHistory(tester);
      await tester.tap(byLogId('queue_history.batch'));
      await tester.pumpAndSettle();
    },
    shows: find.text('Part 2'),
  );

  a11ySurface(
    'queue history, sort menu',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await _openHistory(tester);
      await tester.tap(byLogId('queue_history.sort'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueHistorySortName),
  );

  a11ySurface(
    'queue history, clear confirmation',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await _openHistory(tester);
      await tester.tap(byLogId('queue_history.clear'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueHistoryClearTitle),
  );

  a11ySurface(
    'queue history, remove confirmation',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await _openHistory(tester);
      await tester.tap(byLogId('queue_history.remove').first);
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueHistoryRemoveTitle),
  );

  // --- Bulk edit ---

  a11ySurface(
    'bulk edit',
    home: () => const QueueBulkEditScreen(itemIds: [101, 102]),
    shows: find.text(pl.queueBulkTitle(2)),
  );

  a11ySurface(
    'bulk edit, printer select open',
    home: () => const QueueBulkEditScreen(itemIds: [101, 102]),
    arrange: (tester) async {
      await tester.tap(byLogId('queue_bulk.printer'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueBulkUnassigned),
  );

  a11ySurface(
    'bulk edit, a change picked',
    home: () => const QueueBulkEditScreen(itemIds: [101, 102]),
    arrange: (tester) async {
      await tester.tap(
        find.descendant(
          of: byLogId('queue_bulk.timelapse'),
          matching: find.text(pl.commonOn),
        ),
      );
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueBulkApply),
  );

  // --- The print form ---

  QueueEditScreen edit(QueueItem item) => QueueEditScreen(item: item);

  a11ySurface(
    'edit form',
    home: () => edit(_demoItem()),
    shows: find.text(pl.queueEditTitle),
  );

  a11ySurface(
    'edit form, printer select open',
    home: () => edit(_demoItem()),
    arrange: (tester) async {
      await openQueueFormPrinterSelect(tester);
    },
    shows: byLogId('queue_edit.printer'),
  );

  a11ySurface(
    'edit form, print options and preheat unfolded',
    home: () => edit(_demoItem()),
    arrange: (tester) async {
      await openQueueFormSection(tester, 'queue_edit.print_options_section');
      await openQueueFormSection(tester, 'queue_edit.preheat_section');
    },
    shows: byLogId('queue_edit.timelapse'),
  );

  a11ySurface(
    'edit form, scheduled for a time',
    home: () => edit(_demoItem()),
    arrange: (tester) async {
      await tester.tap(
        find.descendant(
          of: byLogId('queue_edit.schedule_type'),
          matching: find.text(pl.queueScheduleSchedule),
        ),
      );
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue_edit.pick_time'),
  );

  a11ySurface(
    'edit form, date picker',
    home: () => edit(_demoItem()),
    arrange: (tester) async {
      await tester.tap(
        find.descendant(
          of: byLogId('queue_edit.schedule_type'),
          matching: find.text(pl.queueScheduleSchedule),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue_edit.pick_time'));
      await tester.pumpAndSettle();
    },
    shows: find.byType(DatePickerDialog),
  );

  a11ySurface(
    'edit form, G-code injection on a model without a snippet',
    home: () => edit(_demoItem(gcodeInjection: true)),
    shows: byLogId('queue_edit.gcode_injection'),
  );

  a11ySurface(
    'edit form, held for review',
    overrides: [awaitingReviewProvider.overrideWithValue(true)],
    home: () => edit(_demoItem()),
    shows: find.text(pl.queueEditAwaitingReviewNote),
  );

  // "Any X1C" job: the filament override rows instead of the mapping.
  final anyModel = _demoItem(printerId: null, targetModel: 'X1C');

  a11ySurface(
    'edit form, any printer of a model',
    home: () => edit(anyModel),
    shows: find.text(pl.queueEditFilamentOverride),
  );

  a11ySurface(
    'edit form, filament override menu open',
    home: () => edit(anyModel),
    arrange: (tester) async {
      await tester.ensureVisible(byLogId('queue_edit.picker').first);
      await tester.tap(byLogId('queue_edit.picker').first);
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue_edit.menu_item'),
  );

  a11ySurface(
    'edit form, model and location of an unsliced file',
    home: () => edit(
      QueueItem.fromJson({
        'id': 150,
        'position': 9,
        'status': 'pending',
        'target_model': 'P1S',
        'library_file_id': 6,
        'library_file_name': 'Crimper 24 mm',
        'cost_center_id': 1,
      }),
    ),
    shows: byLogId('queue_edit.target_model'),
  );

  a11ySurface(
    'edit form, filament mapping opened',
    home: () => edit(_demoItem()),
    arrange: (tester) async {
      await tester.ensureVisible(byLogId('queue_edit.mapping'));
      await tester.tap(byLogId('queue_edit.mapping'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue_mapping.confirm'),
  );

  // --- Billing states of the form ---
  //
  // A job without a cost center is held to the select, so these use an item
  // queued before billing; the demo's own server answers the "pick" step.

  final unbilled = _demoItem(costCenterId: null);

  a11ySurface(
    'edit form, cost center pick',
    home: () => edit(unbilled),
    shows: byLogId('queue_edit.cost_center'),
  );

  for (final (name, centers, shown)
      in <(String, Future<List<CostCenter>?> Function(), Finder)>[
        (
          'none to print to',
          () async => const <CostCenter>[],
          find.text(pl.queueBillingNoCostCenter),
        ),
        (
          'listing refused',
          () async => null,
          find.text(pl.queueBillingCostCentersRefused),
        ),
        (
          'listing failed',
          () async => throw StateError('unreachable'),
          byLogId('queue_edit.cost_center_retry'),
        ),
      ]) {
    a11ySurface(
      'edit form, cost centers: $name',
      overrides: [
        printableCostCentersProvider.overrideWith((ref) => centers()),
      ],
      home: () => edit(unbilled),
      shows: shown,
    );
  }

  a11ySurface(
    'edit form, cost centers: loading',
    overrides: [
      printableCostCentersProvider.overrideWith(
        (ref) => Completer<List<CostCenter>?>().future,
      ),
    ],
    home: () => edit(unbilled),
    shows: find.text(pl.queueCostCenterTitle),
  );

  // --- Create mode ---

  // The demo's two-plate, two-tone 3MF (library file 7).
  final twoPlates = QueueItem.draft(
    libraryFileId: 7,
    name: 'Mop station',
    printerId: 1,
  );

  QueueEditScreen create() =>
      QueueEditScreen(item: twoPlates, mode: QueueEditMode.create);

  a11ySurface(
    'create form',
    home: create,
    shows: find.text(pl.queueCreateTitle),
  );

  a11ySurface(
    'create form, plate sheet',
    home: create,
    arrange: (tester) async {
      await tester.ensureVisible(byLogId('queue_edit.plate'));
      await tester.tap(byLogId('queue_edit.plate'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue_edit.plate_option'),
  );

  a11ySurface(
    'create form, several copies',
    home: create,
    arrange: (tester) async {
      await tester.ensureVisible(byLogId('queue_edit.copies_up'));
      await tester.tap(byLogId('queue_edit.copies_up'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueEditCopiesOrder),
  );

  a11ySurface(
    'create form, an old server without orders',
    overrides: [batchOrdersProvider.overrideWithValue(const AsyncData(false))],
    home: create,
    arrange: (tester) async {
      await tester.ensureVisible(byLogId('queue_edit.copies_up'));
      await tester.tap(byLogId('queue_edit.copies_up'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.queueEditCopiesHint),
  );

  // --- The filament mapping sheet ---

  a11ySurface(
    'mapping sheet, slot picker',
    home: () => const QueueScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('queue.start_next'));
      await tester.pumpAndSettle();
      await tester.tap(a11yByLogIdStarting('queue_mapping.slot').first);
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue_mapping.tray_auto'),
  );

  a11ySurface(
    'mapping sheet, without a source file',
    home: () => _mappingLauncher(QueueItem.draft(name: 'No file'), 1),
    arrange: a11yOpenLauncher,
    shows: find.text(pl.mappingNoSlots),
  );

  for (final (name, item, printer) in <(String, QueueItem, int)>[
    ('two-tone plate on the X1C', twoPlates, 1),
    ('dual-nozzle printer', _demoItem(printerId: 6), 6),
  ]) {
    a11ySurface(
      'mapping dialog (controller): $name',
      home: () => _mappingLauncher(item, printer, dialog: true),
      arrange: a11yOpenLauncher,
      shows: byLogId('queue_mapping.close'),
      // Only the landscape controller opens it, and its layout scales to the
      // window: a phone portrait window would measure a shrunken dialog.
      window: landscapeRedmi,
    );
  }

  // --- The H2C nozzle rack, in the form's mapping ---

  final rackForm = queueFormOverrides(
    printers: const [printerH2C],
    nozzleRack: const [
      NozzleRackSlot(id: 16, nozzleDiameter: '0.4', nozzleType: 'HS01'),
      NozzleRackSlot(id: 17, nozzleDiameter: '0.6', nozzleType: 'HS01'),
      NozzleRackSlot(id: 18, nozzleDiameter: '0.4', nozzleType: 'HS01'),
      NozzleRackSlot(id: 19, nozzleDiameter: '', nozzleType: ''),
      NozzleRackSlot(id: 20, nozzleDiameter: '', nozzleType: ''),
      NozzleRackSlot(id: 21, nozzleDiameter: '', nozzleType: ''),
    ],
    requirements: FilamentRequirement.parseList({
      'filaments': [
        for (final slot in [1, 2])
          {
            'slot_id': slot,
            'type': 'PLA',
            'color': '#FF0000',
            'group_id': slot,
            'group': {
              'on_rack': true,
              'nozzle_diameter': '0.40',
              'volume_type': 'Standard',
            },
          },
      ],
    }),
  );

  Future<void> openRackMapping(WidgetTester tester) async {
    await tester.ensureVisible(byLogId('queue_edit.mapping'));
    await tester.tap(byLogId('queue_edit.mapping'));
    await tester.pumpAndSettle();
  }

  a11ySurface(
    'rack mapping',
    demo: false,
    overrides: layerOverrides([noServerProfileOverride], rackForm),
    home: () => QueueEditScreen(
      item: archiveDraft(model: 'H2C'),
      mode: QueueEditMode.create,
    ),
    arrange: openRackMapping,
    shows: byLogId('queue_mapping.rack'),
  );

  a11ySurface(
    'rack mapping, position picker',
    demo: false,
    overrides: layerOverrides([noServerProfileOverride], rackForm),
    home: () => QueueEditScreen(
      item: archiveDraft(model: 'H2C'),
      mode: QueueEditMode.create,
    ),
    arrange: (tester) async {
      await openRackMapping(tester);
      await tester.tap(byLogId('queue_mapping.rack').first);
      await tester.pumpAndSettle();
    },
    shows: byLogId('queue_mapping.rack_position_1'),
  );
}

/// A screen with one button that opens the mapping sheet (or its dialog form,
/// which only the single-printer controller opens) on [item].
Widget _mappingLauncher(QueueItem item, int printerId, {bool dialog = false}) =>
    A11yLauncher(
      (context) => showQueueMappingSheet(
        context,
        item: item,
        printerId: printerId,
        confirmLabel: pl.queueStart,
        dialogScale: dialog ? 1 : null,
      ),
    );
