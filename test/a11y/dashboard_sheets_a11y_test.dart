import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/models/ams_history.dart';
import 'package:bambuddy_mobile/core/models/heater_history.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/printer_card.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the dashboard's printer card and
/// every sheet and dialog that opens from it: the card in each state (printing,
/// paused, idle, offline, collapsed, plate waiting, HMS fault, dual nozzle,
/// control refused), its expanded details, the temperature, fan, movement,
/// drying, AMS slot, slot configuration and history sheets, and the stop, plug,
/// feed-direction, reset and colour dialogs. The screen around the card is in
/// dashboard_a11y_test.dart. Not covered: the camera and file-manager screens
/// the header buttons push (their features own them) and the QR scanner of the
/// spool picker (a camera view, unreachable on a host).
///
/// The card is built straight from a demo status, not through the dashboard, so
/// one card is measured at a time on the dashboard's own backdrop; the fixed
/// fixtures start from the demo's status JSON and change only the field the
/// state is about.
void main() {
  setUpAll(() => HmsCatalog.instance.load(const Locale('pl')));

  // --- the card, as the demo fleet shows it -----------------------------------

  for (final (name, id, shows) in [
    ('printing', 1, byLogId('controls.stop')),
    ('idle', 2, byLogId('printer.details_toggle')),
    ('offline', 3, find.text(pl.statusOffline)),
    ('dual nozzle printing', 6, byLogId('printer.temperature_nozzle_2')),
    ('accessory fans', 4, byLogId('printer.details_toggle')),
  ]) {
    _card('card, $name', demoId: id, shows: shows);
  }

  _card(
    'card, collapsed, printing',
    demoId: 1,
    collapsed: true,
    shows: byLogId('printer.expand'),
  );
  _card(
    'card, collapsed, offline',
    demoId: 3,
    collapsed: true,
    shows: byLogId('printer.expand'),
  );

  // --- the card from a fixed status -----------------------------------------------

  _card(
    'card, paused',
    status: _status(1, {'state': 'PAUSE'}),
    shows: byLogId('controls.resume'),
  );
  _card(
    'card, preparing',
    status: _status(1, {'progress': 0, 'layer_num': 0, 'remaining_time': 0}),
    shows: byLogId('controls.stop'),
  );
  _card(
    'card, roster without a status',
    printer: _printer(1),
    shows: find.text(pl.statusOffline),
  );
  _card(
    'card, control refused',
    overrides: [_refused],
    status: _status(1, {}),
    shows: find.text(pl.ctrlForbidden),
  );

  for (final (name, connected) in [('online', true), ('offline', false)]) {
    _card(
      'card, plate waiting, $name',
      overrides: [
        requirePlateClearProvider.overrideWithValue(const AsyncData(true)),
      ],
      status: _status(1, {
        'state': 'FINISH',
        'connected': connected,
        ..._idle,
        'awaiting_plate_clear': true,
      }),
      shows: byLogId('printer.plate_clear'),
    );
  }

  _card(
    'card, fault listed',
    status: _status(1, {
      'hms_errors': [_fault],
    }),
    shows: byLogId('printer.hms_expand'),
  );
  _card(
    'card, fault open',
    status: _status(1, {
      'hms_errors': [_fault],
    }),
    arrange: (tester) => a11yTap(tester, byLogId('printer.hms_expand')),
    shows: byLogId('printer.hms_dismiss_all'),
  );
  _card(
    'card, fault stop confirmation',
    status: _status(1, {
      'hms_errors': [_fault],
    }),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('printer.hms_expand'));
      await a11yTap(tester, byLogId('printer.hms_stop_printing'));
    },
    shows: byLogId('printer.hms_stop_confirm.confirm'),
  );

  // --- details expanded -----------------------------------------------------------

  for (final (name, status, demoId) in <(String, PrinterStatus?, int?)>[
    ('printing', null, 1),
    ('idle with an AMS and a tagged spool', null, 2),
    ('dual nozzle, idle', _status(6, _idle), null),
    ('accessory fans, idle', null, 4),
    ('external spools', _status(1, {..._idle, 'vt_tray': _external}), null),
  ]) {
    _card(
      'card details, $name',
      demoId: demoId,
      status: status,
      arrange: _openDetails,
      shows: byLogId('printer.details_toggle'),
    );
  }

  // --- temperature sheet ----------------------------------------------------------

  for (final (name, status, tile) in <(String, PrinterStatus, String)>[
    ('nozzle', _status(1, _idle), 'printer.temperature_nozzle'),
    ('bed', _status(1, _idle), 'printer.temperature_bed'),
    // The flap in cooling dims the target and disables Set.
    ('chamber, cooling flap', _status(6, _idle), 'printer.temperature_chamber'),
    (
      'chamber, heating flap',
      _status(6, {..._idle, 'airduct_mode': 1}),
      'printer.temperature_chamber',
    ),
    ('second nozzle', _status(6, _idle), 'printer.temperature_nozzle_2'),
  ]) {
    _card(
      'temperature sheet, $name',
      status: status,
      arrange: (tester) => a11yTap(tester, byLogId(tile)),
      shows: byLogId('temperature.set'),
    );
  }

  // Mid-print the nozzle switch is locked.
  _card(
    'temperature sheet, nozzle switch locked mid-print',
    demoId: 6,
    arrange: (tester) =>
        a11yTap(tester, byLogId('printer.temperature_nozzle_2')),
    shows: byLogId('printer.switch_nozzle'),
  );

  // --- heater history -------------------------------------------------------------
  // A tab of the temperature sheet, and the whole sheet of a tile that cannot be
  // set.

  Future<void> openHistoryTab(WidgetTester tester, String tile) async {
    await a11yTap(tester, byLogId(tile));
    await a11yTap(tester, byLogId('temperature.tab_history'));
    await a11yRealTime(tester, real: const Duration(milliseconds: 300));
    // The chart's own timer starts when the answer lands.
    await a11ySettle(tester, const Duration(milliseconds: 500));
  }

  _card(
    'heater history',
    status: _status(6, _idle),
    arrange: (tester) => openHistoryTab(tester, 'printer.temperature_chamber'),
    shows: byLogId('sheet.heater_history'),
  );
  _card(
    'heater history, a week',
    status: _status(6, _idle),
    arrange: (tester) async {
      await openHistoryTab(tester, 'printer.temperature_nozzle');
      await a11yTap(tester, find.text(pl.sensorHistoryRange7d));
      await a11yRealTime(tester, real: const Duration(milliseconds: 300));
    },
    shows: byLogId('sheet.heater_history'),
  );
  _card(
    'heater history, nothing recorded',
    overrides: [
      heaterHistoryDataProvider.overrideWith(
        (ref, q) async =>
            HeaterHistory(printerId: q.printerId, series: const []),
      ),
    ],
    status: _status(6, _idle),
    arrange: (tester) => openHistoryTab(tester, 'printer.temperature_nozzle'),
    shows: find.text(pl.sensorHistoryEmpty),
  );
  _card(
    'heater history, load failed',
    overrides: [
      heaterHistoryDataProvider.overrideWith(
        // Not an API exception: those are worded by their own code, and the
        // strip's own message is the surface here.
        (ref, q) async => throw StateError('history failed'),
      ),
    ],
    status: _status(6, _idle),
    arrange: (tester) => openHistoryTab(tester, 'printer.temperature_nozzle'),
    shows: find.text(pl.sensorHistoryError),
  );
  _card(
    'heater history, a tile that cannot be set',
    status: _status(6, _idle),
    overrides: [
      controlRefusedProvider(ControlPermission.control).overrideWithValue(true),
    ],
    arrange: (tester) async {
      await a11yTap(tester, byLogId('printer.temperature_chamber'));
      await a11yRealTime(tester, real: const Duration(milliseconds: 300));
    },
    shows: byLogId('sheet.heater_history'),
  );

  // --- fan and movement sheets ----------------------------------------------------

  _card(
    'fan sheet',
    status: _status(1, _idle),
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.fan_part'));
    },
    shows: byLogId('fan.set'),
  );
  _card(
    'fan sheet, accessory fan',
    demoId: 4,
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.fan_aux2'));
    },
    shows: byLogId('fan.set'),
  );
  _card(
    'movement sheet',
    demoId: 2,
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.move'));
    },
    shows: byLogId('movement.step_preset'),
  );
  _card(
    'movement sheet, dual nozzle',
    status: _status(6, _idle),
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.move'));
    },
    shows: byLogId('movement.step_preset'),
  );

  // --- AMS history ----------------------------------------------------------------

  _card(
    'ams history, humidity',
    status: _status(1, _idle),
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.ams_meta').first);
      await a11yRealTime(tester, real: const Duration(milliseconds: 300));
    },
    shows: byLogId('sheet.ams_history'),
  );
  _card(
    'ams history, temperature and a week',
    status: _status(1, _idle),
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.ams_meta').last);
      await _tapSegment<int>(tester, 3);
      await a11yRealTime(tester, real: const Duration(milliseconds: 300));
    },
    shows: byLogId('sheet.ams_history'),
  );
  _card(
    'ams history, nothing recorded',
    overrides: [
      amsHistoryDataProvider.overrideWith(
        (ref, q) async => AmsHistory(
          printerId: q.printerId,
          amsId: q.amsId,
          points: const [],
        ),
      ),
    ],
    status: _status(1, _idle),
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.ams_meta').first);
    },
    shows: find.text(pl.sensorHistoryEmpty),
  );
  _card(
    'ams history, load failed',
    overrides: [
      amsHistoryDataProvider.overrideWith(
        // Not an API exception: those are worded by their own code, and the
        // strip's own message is the surface here.
        (ref, q) async => throw StateError('history failed'),
      ),
    ],
    status: _status(1, _idle),
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('printer.ams_meta').first);
    },
    shows: find.text(pl.sensorHistoryError),
  );

  // --- drying ---------------------------------------------------------------------

  Future<void> openDrying(WidgetTester tester) async {
    await _openDetails(tester);
    await a11yTap(tester, byLogId('printer.drying'));
  }

  _card(
    'drying sheet',
    status: _status(1, _idle),
    arrange: openDrying,
    shows: byLogId('drying.start'),
  );
  _card(
    'drying sheet, filament menu',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openDrying(tester);
      await a11yTap(tester, byLogId('drying.filament'));
    },
    shows: a11yByLogIdStarting('drying.filament_option'),
  );
  _card(
    'drying sheet, start after a delay',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openDrying(tester);
      await a11yTap(tester, byLogId('drying.start_mode.delay'));
    },
    shows: byLogId('drying.schedule'),
  );
  _card(
    'drying sheet, start at a time',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openDrying(tester);
      await a11yTap(tester, byLogId('drying.start_mode.at_time'));
    },
    shows: byLogId('drying.pick_time'),
  );
  _card(
    'drying sheet, date picker',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openDrying(tester);
      await a11yTap(tester, byLogId('drying.start_mode.at_time'));
      await a11yTap(tester, byLogId('drying.pick_time'));
    },
    shows: find.byType(DatePickerDialog),
  );
  _card(
    'drying sheet, running',
    status: _status(1, {..._idle, 'ams': _drying(1)}),
    arrange: openDrying,
    shows: byLogId('drying.stop'),
  );
  // The run the delay mode schedules shows as a row under the AMS header.
  _card(
    'drying scheduled, banner on the card',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openDrying(tester);
      await a11yTap(tester, byLogId('drying.start_mode.delay'));
      await a11yTap(tester, byLogId('drying.schedule'));
    },
    shows: byLogId('printer.drying_schedule_cancel'),
  );

  // --- slot sheets ----------------------------------------------------------------

  Future<void> openSlot(WidgetTester tester, [int index = 0]) async {
    await _openDetails(tester);
    await a11yTap(tester, _slotRows.at(index));
  }

  _card(
    'slot sheet, idle',
    status: _status(1, _idle),
    arrange: openSlot,
    shows: byLogId('sheet.assign_spool'),
  );
  _card(
    'slot sheet, empty slot',
    status: _status(1, _idle),
    arrange: (tester) => openSlot(tester, 3),
    shows: byLogId('sheet.assign_spool'),
  );
  // Mid-print the load, unload and re-read buttons are off and a hint says why.
  _card(
    'slot sheet, printing',
    demoId: 1,
    arrange: openSlot,
    shows: find.text(pl.amsActionsWhilePrinting),
  );
  _card(
    'slot sheet, tagged spool not on the shelf',
    demoId: 2,
    arrange: (tester) => openSlot(tester, 2),
    shows: byLogId('assign_spool.add_to_inventory'),
  );
  _card(
    'slot sheet, nothing matches the search',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openSlot(tester);
      await tester.enterText(
        find.descendant(
          of: byLogId('assign_spool.search'),
          matching: find.byType(TextField),
        ),
        'zzzz',
      );
    },
    shows: byLogId('assign_spool.search'),
  );
  _card(
    'slot sheet, external spool',
    status: _status(1, {..._idle, 'vt_tray': _external}),
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, _slotRows.last);
    },
    shows: byLogId('sheet.assign_spool'),
  );
  // A Filament Track Switch asks which nozzle to feed from.
  _card(
    'feed direction dialog',
    status: _status(6, {
      ..._idle,
      'fila_switch': {'installed': true, 'ready': true},
    }),
    arrange: (tester) async {
      await openSlot(tester);
      await a11yTap(tester, byLogId('assign_spool.ams_load'));
    },
    shows: byLogId('feed_direction.left'),
  );

  // --- slot configuration ---------------------------------------------------------

  Future<void> openConfig(WidgetTester tester) async {
    await openSlot(tester);
    await a11yTap(tester, byLogId('assign_spool.configure'));
  }

  _card(
    'slot configuration',
    status: _status(1, _idle),
    arrange: openConfig,
    shows: byLogId('sheet.ams_slot_config'),
  );
  _card(
    'slot configuration, preset picked',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openConfig(tester);
      await a11yTap(tester, byLogId('ams_slot_config.preset').last);
    },
    shows: byLogId('ams_slot_config.apply'),
  );
  _card(
    'slot configuration, colour dialog',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openConfig(tester);
      await a11yTap(tester, byLogId('ams_slot_config.colour'));
    },
    shows: byLogId('ams_slot_colour.swatch'),
  );
  _card(
    'slot configuration, reset confirmation',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openConfig(tester);
      await a11yTap(tester, byLogId('ams_slot_config.reset'));
    },
    shows: byLogId('ams_slot_reset.confirm'),
  );

  // The spool list as other shelves leave it.
  _card(
    'slot sheet, spool assigned',
    overrides: [inventoryProvider.overrideWith(_assigned)],
    status: _status(1, _idle),
    arrange: openSlot,
    shows: a11yByLogIdStarting('assign_spool.unassign'),
  );
  _card(
    'slot sheet, empty shelf',
    overrides: [inventoryProvider.overrideWith(_emptyShelf)],
    status: _status(1, _idle),
    arrange: openSlot,
    shows: byLogId('sheet.assign_spool'),
  );
  // Spoolman binds a tagged spool to its slot: no picker, only the bound spool.
  _card(
    'slot sheet, tag bound in Spoolman',
    overrides: [
      inventoryBackendOverride(InventoryBackend.spoolman),
      inventoryProvider.overrideWith(_tagBound),
    ],
    demoId: 2,
    arrange: (tester) => openSlot(tester, 2),
    shows: a11yByLogIdStarting('assign_spool.current'),
  );

  _card(
    'slot configuration, calibration menu',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openConfig(tester);
      await a11yTap(tester, byLogId('ams_slot_config.k_profile'));
    },
    shows: byLogId('ams_slot_config.k_profile.option'),
  );
  _card(
    'slot configuration, every printer shown',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openConfig(tester);
      await a11yTap(tester, byLogId('ams_slot_config.only_this_printer'));
    },
    shows: byLogId('ams_slot_config.only_this_printer'),
  );
  _card(
    'slot configuration, nothing matches the search',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openConfig(tester);
      await tester.enterText(
        find.descendant(
          of: byLogId('ams_slot_config.search'),
          matching: find.byType(TextField),
        ),
        'zzzz',
      );
    },
    shows: find.text(pl.amsSlotConfigNoMatch),
  );

  _card(
    'drying sheet, time picker',
    status: _status(1, _idle),
    arrange: (tester) async {
      await openDrying(tester);
      await a11yTap(tester, byLogId('drying.start_mode.at_time'));
      await a11yTap(tester, byLogId('drying.pick_time'));
      await a11yTap(
        tester,
        find
            .descendant(
              of: find.byType(DatePickerDialog),
              matching: find.byType(TextButton),
            )
            .last,
      );
    },
    shows: find.byType(TimePickerDialog),
  );

  _card(
    'speed menu',
    demoId: 1,
    arrange: (tester) async {
      await _openDetails(tester);
      await a11yTap(tester, byLogId('controls.speed'));
    },
    shows: a11yByLogIdStarting('controls.speed.'),
  );

  // --- dialogs from the card's own controls ---------------------------------------

  _card(
    'stop print confirmation',
    demoId: 1,
    arrange: (tester) => a11yTap(tester, byLogId('controls.stop')),
    shows: byLogId('controls.stop_confirm.confirm'),
  );
  // The P1S's plug is off, so this one asks to switch it on.
  _card(
    'smart plug confirmation, power on',
    demoId: 2,
    arrange: (tester) => a11yTap(tester, byLogId('printer.smart_plug')),
    shows: byLogId('smart_plug.confirm'),
  );
  // Idle, so the plug button is live; powering off asks first.
  _card(
    'smart plug confirmation',
    status: _status(1, _idle),
    arrange: (tester) => a11yTap(tester, byLogId('printer.smart_plug')),
    shows: byLogId('smart_plug.confirm'),
  );
}

// --- fixtures -----------------------------------------------------------------------

/// The demo's status for [id] with [patch] laid over it, parsed as the app parses
/// a server frame.
PrinterStatus _status(int id, Map<String, dynamic> patch) =>
    PrinterStatus.fromJson({...DemoBackend.instance.statusJson(id), ...patch});

Printer _printer(int id) => switch (id) {
  6 => const Printer(id: 6, name: 'H2D', model: 'H2D', nozzleCount: 2),
  _ => Printer(id: id, name: 'X1 Carbon', model: 'X1C', nozzleCount: 1),
};

/// What a printer between jobs reports.
const _idle = <String, dynamic>{
  'state': 'IDLE',
  'current_print': null,
  'subtask_name': null,
  'gcode_file': null,
  'progress': 0,
  'remaining_time': 0,
  'layer_num': 0,
  'total_layers': 0,
  'tray_now': 255,
  'cover_url': null,
};

/// Filament runout as the `print_error` channel reports it, with the two
/// buttons Bambu's catalogue lists for it.
const _fault = <String, dynamic>{
  'code': '0x8004',
  'attr': 0x03008004,
  'module': 3,
  'severity': 3,
  'full_code': '03008004',
  'job_id': '746795586',
  'actions': ['RESUME_PRINTING', 'STOP_PRINTING'],
};

/// The external holder: the left and right spool, ids 254 and 255.
const _external = <Map<String, dynamic>>[
  {
    'id': 254,
    'tray_color': 'FF6A13FF',
    'tray_type': 'PLA',
    'tray_sub_brands': 'PLA Basic',
    'tray_info_idx': 'GFA00',
    'remain': 50,
  },
  {
    'id': 255,
    'tray_color': 'FFFFFFFF',
    'tray_type': 'PETG',
    'tray_info_idx': 'GFG02',
    'remain': 30,
  },
];

/// The demo printer's AMS with its first unit drying, three hours to go.
List<Object?> _drying(int id) {
  final units = List<Object?>.of(
    DemoBackend.instance.statusJson(id)['ams'] as List,
  );
  units[0] = {
    ...units.first! as Map<String, dynamic>,
    'dry_time': 180,
    'dry_status': 2,
  };
  return units;
}

/// The tray UUID of the P1S's tagged slot, which is what Spoolman links by.
const _tagUid = '6F2C41D9A87B4E0359CD12FA8B76E430';

InventoryNotifier _assigned() =>
    FixedInventory(
      InventoryState(
        spools: const [
          Spool(
            id: 42,
            material: 'PLA',
            subtype: 'Basic',
            brand: 'Bambu Lab',
            labelWeight: 1000,
          ),
        ],
        assignments: [
          SpoolAssignment(
            spoolId: 42,
            printerId: 1,
            amsId: 0,
            trayId: 0,
            printerName: 'X1 Carbon',
          ),
        ],
      ),
    );

InventoryNotifier _emptyShelf() => FixedInventory(InventoryState());

/// The spool the P1S's tagged slot carries, known to Spoolman by that tag.
InventoryNotifier _tagBound() => FixedInventory(
  InventoryState(
    spools: const [
      Spool(
        id: 21,
        material: 'PLA',
        subtype: 'Basic',
        brand: 'Bambu',
        labelWeight: 1000,
        tagUid: _tagUid,
      ),
    ],
    linkedTags: const {_tagUid: LinkedSpool(id: 21)},
  ),
);

final _refused = controlRefusedProvider(
  ControlPermission.control,
).overrideWithValue(true);

/// A filament row of an AMS or the external holder; the identifier carries the
/// material (`printer.ams_slot@PLA`), so it is matched by prefix.
final _slotRows = a11yByLogIdStarting('printer.ams_slot');

// --- harness glue -------------------------------------------------------------------

Future<void> _openDetails(WidgetTester tester) =>
    a11yTap(tester, byLogId('printer.details_toggle'));

/// Taps the segment with label number [index] of the open `SegmentedButton<T>`.
Future<void> _tapSegment<T>(WidgetTester tester, int index) => a11yTap(
  tester,
  find
      .descendant(
        of: find.byType(SegmentedButton<T>),
        matching: find.byType(Text),
      )
      .at(index),
);

/// One surface on a printer card. [demoId] builds the card of that demo printer
/// as the live fleet shows it; [status] (with [printer]) a fixed one.
void _card(
  String name, {
  int? demoId,
  PrinterStatus? status,
  Printer? printer,
  bool collapsed = false,
  List<Override> overrides = const [],
  Future<void> Function(WidgetTester tester)? arrange,
  required Finder shows,
}) {
  assert((demoId == null) != (status == null && printer == null));
  a11ySurface(
    name,
    overrides: overrides,
    home: () => _CardHost(
      demoId: demoId,
      item: demoId != null
          ? null
          : PrinterWithStatus(
              printer: printer ?? _printer(status!.id),
              status: status,
            ),
      collapsed: collapsed,
    ),
    arrange: arrange,
    shows: shows,
  );
}

/// The card on the dashboard's own backdrop, in the list's scroll view, built
/// the way the dashboard builds it.
class _CardHost extends ConsumerWidget {
  const _CardHost({this.demoId, this.item, this.collapsed = false});

  final int? demoId;
  final PrinterWithStatus? item;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var shown = item;
    if (demoId != null) {
      final roster = ref.watch(dashboardProvider).printers;
      if (roster != null) {
        shown = withLiveStatuses(
          roster,
          ref.watch(printerStatusesProvider),
        ).firstWhere((p) => p.printer.id == demoId);
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: DashTokens.of(context).backgroundGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          child: shown == null
              ? const SizedBox.shrink()
              : PrinterCard(
                  key: ValueKey(shown.printer.id),
                  item: shown,
                  collapsed: collapsed,
                  onCollapsedChanged: (_) {},
                ),
        ),
      ),
    );
  }
}
