import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/models/slice_job.dart';
import 'package:bambuddy_mobile/core/slicer/filament_slot_options.dart';
import 'package:bambuddy_mobile/core/slicer/process_schema_catalog.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:bambuddy_mobile/features/slicer/process_settings_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the slice form and the process
/// settings: the form for each kind of demo source (a plain 3MF, the two-plate
/// two-tone 3MF, an STL, a STEP the server refuses), its pickers and sheets,
/// the pipeline bar, the progress dialog in each of its states, and the process
/// settings in every mode, page, search result and error state. The harness and
/// the rules are in a11y_harness.dart. Demo library files: 6 plain 3MF, 7
/// two-plate two-tone 3MF, 8 STL, 9 STEP. The slice form is only reachable
/// through [showSliceScreen], so every surface opens it from a launcher. Not
/// covered: the progress dialog's `AppApiException` branch, which only a failed
/// poll reaches and the demo never fails one.

const _plain = SliceTarget.libraryFile(6, 'Crimper 24 mm.3mf');
const _twoTone = SliceTarget.libraryFile(7, 'Mop station.3mf');
const _stl = SliceTarget.libraryFile(8, 'Rack rails.stl');
const _step = SliceTarget.libraryFile(9, 'Server rack – plate 22.step');

/// Opens the form on the launcher and runs [then] on it.
Future<void> Function(WidgetTester) _form(
  Future<void> Function(WidgetTester tester) then,
) => (tester) async {
  await a11yOpenLauncher(tester, settle: const Duration(seconds: 2));
  await then(tester);
};

Future<void> _submit(WidgetTester tester) =>
    a11yTap(tester, byLogId('slice.submit'));

/// A slice that finishes at its first poll, so the dialog's result is on show
/// and no poll is left running. Restored after the test.
void _instantSlices() {
  final before = DemoBackend.sliceSeconds;
  DemoBackend.sliceSeconds = 0;
  addTearDown(() => DemoBackend.sliceSeconds = before);
}

/// A server whose slice job comes back failed.
class _FailingJobs extends SlicerRepository {
  _FailingJobs(super.dio, super.versions);

  @override
  Future<SliceJob> job(int jobId) async => SliceJob.fromJson({
    'job_id': jobId,
    'status': 'failed',
    'error_detail':
        'Slicing failed: filament preset is not compatible with the selected '
        'printer',
  });
}

void main() {
  // The vendored option metadata comes through the asset bundle, whose reads a
  // widget test's fake clock never lets finish: read it here, in real time.
  setUpAll(ProcessSchemaCatalog.instance.load);

  // --- The slice form ---

  for (final (name, target) in const [
    ('plain 3MF', _plain),
    ('two-plate two-tone 3MF', _twoTone),
    ('STL', _stl),
  ]) {
    a11ySurface(
      'slice form, $name',
      home: () => _sliceLauncher(target),
      arrange: (tester) =>
          a11yOpenLauncher(tester, settle: const Duration(seconds: 2)),
      shows: byLogId('slice.submit'),
    );
  }

  a11ySurface(
    'slice form, as designed',
    home: () => _sliceLauncher(_twoTone),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.as_designed'));
    }),
    shows: byLogId('slice.as_designed'),
  );

  a11ySurface(
    'slice form, every plate',
    home: () => _sliceLauncher(_twoTone),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.all_plates'));
    }),
    shows: byLogId('slice.all_plates'),
  );

  a11ySurface(
    'slice form, filters off',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.only_online'));
      await a11yTap(tester, byLogId('slice.only_loaded'));
    }),
    shows: byLogId('slice.only_online'),
  );

  a11ySurface(
    'slice form, layout switches on',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.auto_orient'));
      await a11yTap(tester, byLogId('slice.auto_arrange'));
    }),
    shows: byLogId('slice.auto_orient'),
  );

  // --- Sheets opened from the form ---

  a11ySurface(
    'slice form, plate sheet',
    home: () => _sliceLauncher(_twoTone),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.plate'));
    }),
    shows: byLogId('queue_edit.plate_option'),
  );

  a11ySurface(
    'slice form, bed type sheet',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.bed_type'));
    }),
    shows: find.text(pl.sliceBedDefault),
  );

  // The first `slice.slot` is the printer, the second the process preset and
  // the rest are filaments.
  for (final (name, index) in const [('printer', 0), ('process', 1)]) {
    a11ySurface(
      'preset sheet, $name',
      home: () => _sliceLauncher(_plain),
      arrange: _form((tester) async {
        await tester.tap(byLogId('slice.slot').at(index));
        await a11ySettle(tester, const Duration(seconds: 1));
      }),
      shows: byLogId('slice.preset_option'),
    );
  }

  a11ySurface(
    'preset sheet, show all',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await tester.tap(byLogId('slice.slot').at(1));
      await a11ySettle(tester, const Duration(seconds: 1));
      await tester.tap(byLogId('slice.show_all_presets'));
      await a11ySettle(tester, const Duration(seconds: 1));
    }),
    shows: byLogId('slice.preset_option'),
  );

  Future<void> openFilamentSheet(WidgetTester tester) async {
    await tester.tap(byLogId('slice.slot').at(2));
    await a11ySettle(tester, const Duration(seconds: 1));
  }

  a11ySurface(
    'filament sheet',
    home: () => _sliceLauncher(_plain),
    arrange: _form(openFilamentSheet),
    shows: find.text(pl.sliceNeedsMaterial('PLA')),
  );

  a11ySurface(
    'filament sheet, profiles tab',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await openFilamentSheet(tester);
      await tester.tap(find.text(pl.sliceTabProfiles));
      await a11ySettle(tester, const Duration(seconds: 1));
    }),
    shows: byLogId('slice.show_all_presets'),
  );

  a11ySurface(
    'filament sheet, profiles tab with everything shown',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await openFilamentSheet(tester);
      await tester.tap(find.text(pl.sliceTabProfiles));
      await a11ySettle(tester, const Duration(seconds: 1));
      await tester.tap(byLogId('slice.show_all_presets'));
      await a11ySettle(tester, const Duration(seconds: 1));
    }),
    shows: byLogId('slice.preset_option'),
  );

  // --- The pipeline bar ---

  a11ySurface(
    'pipeline apply sheet',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.pipeline_apply'));
    }),
    shows: byLogId('slice.pipeline_option'),
  );

  a11ySurface(
    'pipeline save dialog',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.pipeline_save'));
    }),
    shows: byLogId('pipeline.save_confirm'),
  );

  a11ySurface(
    'pipeline save dialog, name typed',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await a11yTap(tester, byLogId('slice.pipeline_save'));
      await tester.enterText(byLogId('pipeline.name_field'), 'Nightly bins');
      await a11ySettle(tester, const Duration(seconds: 1));
    }),
    shows: byLogId('pipeline.save_confirm'),
  );

  // --- Submitting ---

  a11ySurface(
    'slice refused (STEP)',
    home: () => _sliceLauncher(_step),
    arrange: _form(_submit),
    shows: find.text(pl.sliceRefusedStep),
  );

  a11ySurface(
    'progress dialog, waiting for the sidecar',
    home: () => _sliceLauncher(_plain),
    arrange: _form(_submit),
    shows: find.text(pl.sliceInProgress),
  );

  // The demo job reports a stage once a real second has passed since the
  // request, and the clock a widget test fakes does not move that one: wait it
  // out for real, then let the dialog's poll (every 1.5 s) read it. The poll
  // after that is 1.5 s further, past the point the harness measures at.
  a11ySurface(
    'progress dialog, running',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      await tester.tap(byLogId('slice.submit'));
      await a11ySettle(tester, const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)),
      );
      await a11ySettle(tester, const Duration(milliseconds: 1500));
    }),
    shows: find.text(pl.sliceInProgress),
  );

  a11ySurface(
    'progress dialog, done',
    home: () => _sliceLauncher(_plain),
    arrange: _form((tester) async {
      _instantSlices();
      await _submit(tester);
    }),
    shows: byLogId('slice_progress.close'),
  );

  a11ySurface(
    'progress dialog, failed',
    overrides: [
      slicerRepositoryProvider.overrideWith(
        (ref) => _FailingJobs(
          ref.watch(apiClientProvider).dio,
          ref.watch(serverVersionServiceProvider),
        ),
      ),
    ],
    home: () => _sliceLauncher(_plain),
    arrange: _form(_submit),
    shows: find.text(pl.sliceFailed),
  );

  // --- Process settings ---

  const preset = ('local', 'q-020-std');

  ProcessSettingsScreen settings({
    Map<String, Object> values = const {},
    List<FilamentSlotChoice> slots = const [],
    ProcessPresetRef ref = preset,
  }) => ProcessSettingsScreen(
    preset: ref,
    initialValues: values,
    onChanged: (_) {},
    filamentSlots: slots,
  );

  Future<void> mode(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: byLogId('process_settings.mode'),
        matching: find.text(label),
      ),
    );
    await a11ySettle(tester, const Duration(seconds: 1));
  }

  Future<void> page(WidgetTester tester, String name) async {
    final chip = find.descendant(
      of: byLogId('process_settings.page'),
      matching: find.text(name),
    );
    // The later pages sit past the right edge of the chip row.
    await tester.scrollUntilVisible(
      chip,
      100,
      scrollable: find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await a11ySettle(tester, const Duration(seconds: 1));
  }

  Future<void> expertPage(WidgetTester tester, String name) async {
    await mode(tester, pl.processSettingsModeExpert);
    await page(tester, name);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(byLogId('process_settings.search'), query);
    await a11ySettle(tester, const Duration(seconds: 1));
  }

  a11ySurface(
    'process settings',
    home: () => settings(),
    arrange: (tester) =>
        a11yRealTime(tester, frames: const Duration(seconds: 1)),
    shows: find.text(pl.processSettingsTitle),
  );

  a11ySurface(
    'process settings, advanced',
    home: () => settings(),
    arrange: (tester) async {
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await mode(tester, pl.processSettingsModeAdvanced);
    },
    shows: find.text('Line width'),
  );

  a11ySurface(
    'process settings, expert',
    home: () => settings(),
    arrange: (tester) async {
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await mode(tester, pl.processSettingsModeExpert);
    },
    shows: find.text('Line width'),
  );

  for (final name in const [
    'Strength',
    'Speed',
    'Support',
    'Multimaterial',
    'Others',
  ]) {
    a11ySurface(
      'process settings, $name page',
      home: () => settings(),
      arrange: (tester) async {
        await a11yRealTime(tester, frames: const Duration(seconds: 1));
        await expertPage(tester, name);
      },
      shows: byLogId('process_settings.page'),
    );
  }

  a11ySurface(
    'process settings, search',
    home: () => settings(),
    arrange: (tester) async {
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await search(tester, 'support');
    },
    shows: find.text('Enable support'),
  );

  a11ySurface(
    'process settings, search without a match',
    home: () => settings(),
    arrange: (tester) async {
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await search(tester, 'zzzzzz');
    },
    shows: find.text(pl.processSettingsNoMatches),
  );

  // Layer height far above its limit shows the range error; the other edits
  // show the modified dot, the revert button and "revert all".
  a11ySurface(
    'process settings, edited values',
    home: () => settings(
      values: const {
        'layer_height': '9',
        'wall_loops': '4',
        'sparse_infill_density': '40%',
        'enable_support': true,
      },
    ),
    arrange: (tester) =>
        a11yRealTime(tester, frames: const Duration(seconds: 1)),
    shows: byLogId('process_settings.revert_all'),
  );

  a11ySurface(
    'process settings, a rule greys a row out',
    home: () => settings(),
    arrange: (tester) async {
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await expertPage(tester, 'Support');
    },
    shows: find.text(pl.processSettingsDisabledHint),
  );

  a11ySurface(
    'process settings, enum select open',
    home: () => settings(),
    arrange: (tester) async {
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await tester.tap(byLogId('process_settings.option_enum').first);
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: byLogId('process_settings.option_enum_value'),
  );

  final slots = [
    for (final (i, label) in [
      'Generic PETG @X1C',
      'Fiberlogy ASA @X1C',
    ].indexed)
      FilamentSlotChoice(slot: i + 1, label: label, unused: i == 1),
  ];

  // Slot 7 does not exist on this file, so the select also shows its
  // "missing slot" entry.
  a11ySurface(
    'process settings, filament slot select open',
    home: () => settings(slots: slots, values: const {'support_filament': '7'}),
    arrange: (tester) async {
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await expertPage(tester, 'Support');
      final select = byLogId('process_settings.option_filament').first;
      await tester.ensureVisible(select);
      await tester.tap(select);
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: byLogId('process_settings.option_filament_value'),
  );

  a11ySurface(
    'process settings, defaults unresolved',
    home: () => settings(ref: ('standard', '0.20mm Standard @BBL X1C')),
    arrange: (tester) =>
        a11yRealTime(tester, frames: const Duration(seconds: 1)),
    shows: find.text(pl.processSettingsDefaultsOutdatedSidecar),
  );

  a11ySurface(
    'process settings, unavailable',
    overrides: [presetValuesProvider.overrideWith((ref, arg) async => null)],
    home: () => settings(),
    arrange: (tester) =>
        a11yRealTime(tester, frames: const Duration(seconds: 1)),
    shows: find.text(pl.processSettingsUnavailable),
  );

  // Reached from the slice form, so it carries the form's own slots.
  a11ySurface(
    'process settings from the form',
    home: () => _sliceLauncher(_twoTone),
    arrange: (tester) async {
      await a11yOpenLauncher(tester, settle: const Duration(seconds: 2));
      await a11yRealTime(tester, frames: const Duration(seconds: 1));
      await a11yTap(tester, byLogId('slice.process_settings'));
    },
    shows: find.text(pl.processSettingsTitle),
  );
}

/// A screen with one button that opens the slice form on [target].
Widget _sliceLauncher(SliceTarget target) =>
    A11yLauncher((context) => showSliceScreen(context, target));
