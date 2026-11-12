import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_picker.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/wall/wall_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../features/archive/archive_fakes.dart';
import '../features/queue/queue_fakes.dart';
import '../helpers.dart';
import 'a11y_harness.dart';

/// The demo fleet's ids: 1 is mid-print on an X1C with an AMS, 2 an idle P1S,
/// 3 an offline A1 mini, 4 a P2S with four fans, 6 the dual-nozzle H2D.
const _printing = 1;
const _idle = 2;
const _offline = 3;
const _fourFans = 4;
const _dual = 6;

/// One controller surface on a landscape phone (the shape it is designed for).
void _controller(
  String name, {
  int printer = _printing,
  List<Override> overrides = const [],
  Future<void> Function(WidgetTester tester)? arrange,
  required Finder shows,
  Size window = landscapeRedmi,
  List<double> textScales = a11yTextScales,
}) => a11ySurface(
  'controller, $name',
  window: window,
  home: () => ControllerScreen(printerId: printer),
  overrides: overrides,
  arrange: arrange,
  shows: shows,
  textScales: textScales,
);

/// A phone whose window is 360 dp tall: the body is shorter than the design's
/// (360 dp), so every tab is a page from the normal text size up.
const _shortWindow = Size(891, 360);

Future<void> _openTab(WidgetTester tester, ControllerTab tab) async {
  await tester.ensureVisible(byLogId(tab.logId));
  await tester.tap(byLogId(tab.logId));
  await settle(tester);
}

Future<void> _openPrints(WidgetTester tester, ControllerPrintsView view) async {
  await _openTab(tester, ControllerTab.prints);
  await tester.tap(byLogId(view.logId));
  await settle(tester);
}

/// Settings, on [card] (0 the saver, 1 the display). From a large text size the
/// tab shows one card at a time behind a row of two; at the normal size both are
/// there and nothing is tapped.
Future<void> _openSettings(WidgetTester tester, {int card = 1}) async {
  await _openTab(tester, ControllerTab.settings);
  final picker = byLogId('controller.settings_card');
  if (picker.evaluate().isNotEmpty) await a11yTap(tester, picker.at(card));
}

/// The library's search field, filled and submitted the way the keyboard does.
Future<void> _search(WidgetTester tester, String text) async {
  await a11yTap(tester, byLogId('controller.files.search'));
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await settle(tester);
}

/// A library that could not be read, as after a dropped connection.
class _BrokenFiles extends FileManagerNotifier {
  @override
  Future<FileManagerState> build() async =>
      throw const ApiException(AppErrorCode.connectionError);
}

/// A library with nothing in it.
class _EmptyFiles extends FileManagerNotifier {
  @override
  Future<FileManagerState> build() async => const FileManagerState();
}

/// A queue that could not be read.
class _BrokenQueue extends FakeQueue {
  @override
  Future<List<QueueItem>> build() async =>
      throw const ApiException(AppErrorCode.connectionError);
}

/// An archive that fails every read, not only the first: the notifier retries.
class _BrokenArchives extends FakeArchives {
  @override
  Future<List<Archive>> list({
    int limit = 50,
    int offset = 0,
    int? printerId,
  }) async => throw const ApiException(AppErrorCode.connectionError);
}

/// Rendered contrast and touch targets of the single-printer controller on a
/// landscape phone (the shape it is designed for): every tab, the three Prints
/// views with their empty and failed states, the file, job and print dialogs,
/// the print screen with its mapping sheet, More dialog and time picker, the
/// fault view, the saver, the printer picker, and the confirmations and sheets
/// the tabs open, on the demo fleet unless a state needs an override. Not
/// covered: the skip-objects screen (the dashboard's, pushed from Overview), the
/// live camera stream, an upload under way (it needs the system file picker),
/// and the archive's load-more footer (the demo archive is under one page).
void main() {
  _controller('overview, printing', shows: byLogId('controller.stop'));
  _controller(
    'overview, idle',
    printer: _idle,
    shows: byLogId('controller.light'),
  );
  _controller(
    'overview, offline',
    printer: _offline,
    shows: byLogId('controller.tab_overview'),
  );
  _controller(
    'overview, dual nozzle',
    printer: _dual,
    shows: byLogId('controller.stop'),
  );
  _controller(
    'overview, file preview',
    arrange: (tester) async {
      await _openSettings(tester);
      await a11yTap(tester, byLogId('controller.live_camera'));
      await _openTab(tester, ControllerTab.overview);
    },
    shows: byLogId('controller.stop'),
  );

  _controller(
    'heat, printing',
    arrange: (tester) => _openTab(tester, ControllerTab.heat),
    shows: byLogId('controller.heat_plus'),
  );
  _controller(
    'heat, idle',
    printer: _idle,
    arrange: (tester) => _openTab(tester, ControllerTab.heat),
    shows: byLogId('controller.heat_plus'),
  );
  _controller(
    'heat, four fans',
    printer: _fourFans,
    arrange: (tester) => _openTab(tester, ControllerTab.heat),
    shows: byLogId('controller.fan.aux2'),
  );
  _controller(
    'heat, dual nozzle',
    printer: _dual,
    arrange: (tester) => _openTab(tester, ControllerTab.heat),
    shows: byLogId('controller.heat_plus'),
  );
  _controller(
    'heat, target keypad',
    printer: _idle,
    arrange: (tester) async {
      await _openTab(tester, ControllerTab.heat);
      await a11yTap(tester, byLogId('controller.heat_target').first);
    },
    shows: byLogId('controller.heat_target_set'),
  );

  _controller(
    'move, printing',
    arrange: (tester) => _openTab(tester, ControllerTab.move),
    shows: byLogId('controller.home'),
  );
  _controller(
    'move, idle',
    printer: _idle,
    arrange: (tester) => _openTab(tester, ControllerTab.move),
    shows: byLogId('controller.home'),
  );

  _controller(
    'filament, printing',
    arrange: (tester) => _openTab(tester, ControllerTab.filament),
    shows: byLogId('controller.slot'),
  );
  _controller(
    'filament, idle',
    printer: _idle,
    arrange: (tester) => _openTab(tester, ControllerTab.filament),
    shows: byLogId('controller.load'),
  );

  _controller(
    'settings',
    arrange: (tester) => _openSettings(tester),
    shows: byLogId('controller.keep_awake'),
  );
  _controller(
    'settings, saver',
    arrange: (tester) => _openSettings(tester, card: 0),
    shows: byLogId('controller.saver_after'),
  );

  // Prints, Files.
  _controller(
    'files, root',
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.files),
    shows: byLogId('controller.files.folder'),
  );
  _controller(
    'files, folder',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await a11yTap(tester, byLogId('controller.files.folder').first);
    },
    shows: byLogId('controller.files.file'),
  );
  _controller(
    'files, search field',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await a11yTap(tester, byLogId('controller.files.search'));
    },
    shows: byLogId('controller.files.search_field'),
  );
  _controller(
    'files, search applied',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await _search(tester, 'rack');
    },
    shows: byLogId('controller.files.search_chip'),
  );
  _controller(
    'files, search without a match',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await _search(tester, 'zzz');
    },
    shows: byLogId('controller.files.search_chip'),
  );
  _controller(
    'files, empty library',
    overrides: [fileManagerProvider.overrideWith(_EmptyFiles.new)],
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.files),
    shows: byLogId('controller.files.refresh'),
  );
  _controller(
    'files, library unreadable',
    overrides: [fileManagerProvider.overrideWith(_BrokenFiles.new)],
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.files),
    shows: byLogId('controller.files.retry'),
  );
  _controller(
    'file dialog, not sliced',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await a11yTap(tester, byLogId('controller.files.file').first);
    },
    shows: byLogId('controller.files.dialog.close'),
  );
  _controller(
    'file dialog, printable',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await a11yTap(tester, byLogId('controller.files.folder').first);
      await a11yTap(tester, byLogId('controller.files.file').first);
    },
    shows: byLogId('controller.files.dialog.print'),
  );
  _controller(
    'file dialog, sliced for another model',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      // By name: the nth built match of a lazy list is not the nth row once the
      // list has scrolled.
      await a11yTap(
        tester,
        find.descendant(
          of: byLogId('controller.files.folder'),
          matching: find.text('Server rack'),
        ),
      );
      await a11yTap(tester, byLogId('controller.files.file').first);
    },
    shows: byLogId('controller.files.dialog.print'),
  );
  _controller(
    'file delete confirmation',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await a11yTap(tester, byLogId('controller.files.folder').first);
      await a11yTap(tester, byLogId('controller.files.file').first);
      await a11yTap(tester, byLogId('controller.files.dialog.delete'));
    },
    shows: byLogId('controller.files.delete_confirm'),
  );

  // Prints, Queue.
  _controller(
    'queue',
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.queue),
    shows: byLogId('controller.queue.job'),
  );
  _controller(
    'queue, job dialog',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.queue);
      await a11yTap(tester, byLogId('controller.queue.job').first);
    },
    shows: byLogId('controller.queue.dialog.close'),
  );
  _controller(
    'queue, empty',
    overrides: [queueProvider.overrideWith(FakeQueue.new)],
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.queue),
    shows: byLogId('controller.queue.refresh'),
  );
  _controller(
    'queue, unreadable',
    overrides: [queueProvider.overrideWith(_BrokenQueue.new)],
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.queue),
    shows: byLogId('controller.queue.retry'),
  );

  // Prints, Archive.
  _controller(
    'archive',
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.archive),
    shows: byLogId('controller.archive.print'),
  );
  _controller(
    'archive, print dialog',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.archive);
      await a11yTap(tester, byLogId('controller.archive.print').first);
    },
    shows: byLogId('controller.archive.dialog.close'),
  );
  _controller(
    'archive, empty',
    overrides: [archiveRepositoryProvider.overrideWithValue(FakeArchives())],
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.archive),
    shows: byLogId('controller.archive.refresh'),
  );
  _controller(
    'archive, unreadable',
    overrides: [archiveRepositoryProvider.overrideWithValue(_BrokenArchives())],
    arrange: (tester) => _openPrints(tester, ControllerPrintsView.archive),
    shows: byLogId('controller.archive.retry'),
  );

  _controller(
    'stop confirmation',
    arrange: (tester) => a11yTap(tester, byLogId('controller.stop')),
    shows: byLogId('controller.stop_confirm'),
  );
  _controller(
    'smart plug confirmation',
    printer: _idle,
    arrange: (tester) => a11yTap(tester, byLogId('controller.smart_plug')),
    shows: byLogId('controller.smart_plug_confirm'),
  );
  _controller(
    'move, dual nozzle',
    printer: _dual,
    arrange: (tester) => _openTab(tester, ControllerTab.move),
    shows: byLogId('controller.jog_nozzle'),
  );
  for (final (name, tab) in [
    ('heat', ControllerTab.heat),
    ('move', ControllerTab.move),
  ]) {
    _controller(
      '$name, printer offline',
      printer: _offline,
      arrange: (tester) => _openTab(tester, tab),
      shows: byLogId(tab.logId),
    );
  }
  _controller(
    'queue, start mapping dialog',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.queue);
      await a11yTap(tester, byLogId('controller.queue.job').last);
      await a11yTap(tester, byLogId('controller.queue.dialog.start'));
    },
    shows: byLogId('queue_mapping.confirm'),
  );
  _controller(
    'print screen, time picker',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.files);
      await a11yTap(tester, byLogId('controller.files.folder').first);
      await a11yTap(tester, byLogId('controller.files.file').first);
      await a11yTap(tester, byLogId('controller.files.dialog.print'));
      await a11yTap(tester, byLogId('controller.print.when').at(2));
      await a11yTap(tester, byLogId('controller.print.pick_time'));
    },
    shows: find.byType(DatePickerDialog),
  );

  // Filament sheets the pencils and Dry open (the printer card's own).
  _controller(
    'filament, slot sheet',
    printer: _idle,
    arrange: (tester) async {
      await _openTab(tester, ControllerTab.filament);
      await a11yTap(tester, byLogId('controller.slot_edit').first);
    },
    shows: find.byType(BottomSheet),
  );
  _controller(
    'filament, external spool sheet',
    printer: _idle,
    arrange: (tester) async {
      await _openTab(tester, ControllerTab.filament);
      await a11yTap(tester, byLogId('controller.filament_unit').last);
      await a11yTap(tester, byLogId('controller.slot_edit').first);
    },
    shows: find.byType(BottomSheet),
  );
  _controller(
    'filament, drying sheet',
    arrange: (tester) async {
      await _openTab(tester, ControllerTab.filament);
      await a11yTap(tester, byLogId('controller.dry'));
    },
    shows: find.byType(BottomSheet),
  );

  // Settings: the states of the saver block.
  _controller(
    'settings, screen not held on',
    arrange: (tester) async {
      await _openSettings(tester);
      await a11yTap(tester, byLogId('controller.keep_awake'));
      // The preview button is on the saver's card.
      final picker = byLogId('controller.settings_card');
      if (picker.evaluate().isNotEmpty) await a11yTap(tester, picker.first);
    },
    shows: byLogId('controller.saver_preview'),
  );
  _controller(
    'settings, never-start confirmation',
    arrange: (tester) async {
      await _openSettings(tester, card: 0);
      await a11yTap(tester, byLogId('controller.saver_after').last);
      // From a large text size the row is a select: its last entry is Never.
      final option = byLogId('controller.saver_after.option');
      if (option.evaluate().isNotEmpty) await a11yTap(tester, option.last);
    },
    shows: byLogId('controller.saver_never'),
  );

  // The screen saver, over a printing and over an idle printer.
  for (final (name, printer) in [('job', _printing), ('idle', _idle)]) {
    _controller(
      'screen saver, $name',
      printer: printer,
      arrange: (tester) async {
        await _openTab(tester, ControllerTab.settings);
        await a11yTap(tester, byLogId('controller.saver_preview'));
      },
      shows: find.byType(ControllerSaver),
    );
  }

  // A session the server refuses control to: the lock lines and the missing
  // buttons. Overview needs a running print for its refusal line.
  for (final (name, tab, printer, shows) in [
    (
      'overview',
      ControllerTab.overview,
      _printing,
      find.text(pl.ctrlForbidden),
    ),
    ('heat', ControllerTab.heat, _idle, find.text(pl.ctrlForbidden)),
    ('move', ControllerTab.move, _idle, find.text(pl.ctrlForbidden)),
    ('filament', ControllerTab.filament, _idle, byLogId('controller.slot')),
  ]) {
    _controller(
      '$name, control refused',
      printer: printer,
      overrides: [
        controlRefusedProvider(
          ControlPermission.control,
        ).overrideWithValue(true),
      ],
      arrange: (tester) => _openTab(tester, tab),
      shows: shows,
    );
  }

  _controller(
    'airduct confirmation',
    printer: _dual,
    arrange: (tester) async {
      await _openTab(tester, ControllerTab.heat);
      await a11yTap(tester, byLogId('controller.airduct'));
    },
    shows: byLogId('controller.airduct_print'),
  );

  _controller(
    'printer gone',
    printer: 99,
    shows: find.text(pl.controllerPrinterGone),
  );

  a11ySurface(
    'controller, printer picker',
    window: landscapeRedmi,
    home: () => const _PickerLauncher(),
    arrange: (tester) => a11yTap(tester, find.text('open')),
    shows: byLogId('controller.pick_printer'),
  );

  // The same tabs on a short window, at 100 % and at the 120 % no other surface
  // tries: between the normal size and the reflow (1.3x) the design's box does not
  // grow with the text, so only the room's height tells a tab to become a page.
  for (final (tab, id) in [
    (ControllerTab.overview, 'controller.stop'),
    (ControllerTab.heat, 'controller.heat_plus'),
    (ControllerTab.move, 'controller.home'),
    (ControllerTab.filament, 'controller.slot'),
    (ControllerTab.settings, 'controller.saver_after'),
  ]) {
    _controller(
      'short window, ${tab.name}',
      printer: _dual,
      window: _shortWindow,
      textScales: [1.2, ...a11yTextScales],
      arrange: tab == ControllerTab.overview
          ? null
          : (tester) => _openTab(tester, tab),
      shows: byLogId(id),
    );
  }

  // A paused print with a fault, from a roster of one.
  for (final open in [false, true]) {
    a11ySurface(
      open ? 'controller, fault view' : 'controller, fault chip',
      demo: false,
      window: landscapeRedmi,
      overrides: _faultOverrides,
      home: () => const ControllerScreen(printerId: 1),
      arrange: open
          ? (tester) => a11yTap(tester, byLogId('controller.faults'))
          : null,
      shows: byLogId(
        open ? 'controller.faults_dismiss_all' : 'controller.faults',
      ),
    );
  }

  // The print screen, reached from a file and from an archived print.
  Future<void> openFilePrint(WidgetTester tester) async {
    await _openPrints(tester, ControllerPrintsView.files);
    await a11yTap(tester, byLogId('controller.files.folder').first);
    await a11yTap(tester, byLogId('controller.files.file').first);
    await a11yTap(tester, byLogId('controller.files.dialog.print'));
  }

  _controller(
    'print screen, file',
    arrange: openFilePrint,
    shows: byLogId('controller.print.submit'),
  );
  _controller(
    'print screen, queue',
    arrange: (tester) async {
      await openFilePrint(tester);
      await a11yTap(tester, byLogId('controller.print.when').at(1));
    },
    shows: byLogId('controller.print.submit'),
  );
  _controller(
    'print screen, scheduled',
    arrange: (tester) async {
      await openFilePrint(tester);
      await a11yTap(tester, byLogId('controller.print.when').at(2));
    },
    shows: byLogId('controller.print.pick_time'),
  );
  _controller(
    'print screen, archived print',
    arrange: (tester) async {
      await _openPrints(tester, ControllerPrintsView.archive);
      await a11yTap(tester, byLogId('controller.archive.print').first);
      await a11yTap(tester, byLogId('controller.archive.dialog.print'));
    },
    shows: byLogId('controller.print.submit'),
  );
  _controller(
    'print screen, filament mapping',
    arrange: (tester) async {
      await openFilePrint(tester);
      await a11yTap(tester, byLogId('controller.print.filament').first);
    },
    shows: byLogId('queue_mapping.confirm'),
  );
  _controller(
    'print screen, more options',
    arrange: (tester) async {
      await openFilePrint(tester);
      await a11yTap(tester, byLogId('controller.print.more'));
    },
    shows: byLogId('controller.print.more.close'),
  );
}

/// Opens the printer picker the way the dashboard's menu does.
class _PickerLauncher extends ConsumerWidget {
  const _PickerLauncher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The picker reads the roster once, so something has to be listening.
    ref.watch(wallRosterProvider);
    return Scaffold(
      body: TextButton(
        onPressed: () => openController(context, ref),
        child: const Text('open'),
      ),
    );
  }
}

/// A paused print on a roster of one, with the fault the printer card lists.
final _faultOverrides = [
  fakeServerProfileOverride(),
  fixedDashboardOverride(
    const DashboardState(
      printers: [
        PrinterWithStatus(
          printer: Printer(id: 1, name: 'X1C Warsztat', model: 'P1S'),
          status: PrinterStatus(
            id: 1,
            connected: true,
            state: 'PAUSE',
            hmsErrors: [
              HmsError(
                message: 'Filament has run out.',
                code: '0x8004',
                attr: 0x03008004,
                module: 3,
                severity: 3,
                fullCode: '03008004',
                actions: ['RESUME_PRINTING', 'STOP_PRINTING'],
              ),
            ],
          ),
        ),
      ],
    ),
  ),
  inertStatusesOverride,
  inertSmartPlugsOverride,
];
