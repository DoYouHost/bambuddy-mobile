import 'dart:convert';

import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/slice_job.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/core/slicer/process_schema_catalog.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The slice screen: its shape, and its process-override wiring — whether the
/// entry appears, and what reaches the request body.
///
/// The body is the point. `SliceRequest` forbids no extra fields, so a mistake
/// here does not fail — it slices with settings nobody asked for, or silently
/// without the ones they did.
const _schema = {
  'layer_height': {
    'type': 'coFloat',
    'mode': 'simple',
    'label': 'Layer height',
    'default': 0.2,
  },
  'sparse_infill_density': {
    'type': 'coPercent',
    'mode': 'simple',
    'label': 'Sparse infill density',
    'sidetext': '%',
    'default': 15,
  },
};

const _tree = [
  {
    'page': 'Quality',
    'groups': [
      {
        'group': 'Layer height',
        'options': ['layer_height', 'sparse_infill_density'],
      },
    ],
  },
];

Future<ProcessSchemaCatalog> _catalog() async {
  final catalog = ProcessSchemaCatalog(readAsset: (key) async => switch (key) {
        'assets/slicer/process-schema.json' => jsonEncode(_schema),
        'assets/slicer/process-ui-tree.json' => jsonEncode(_tree),
        _ => jsonEncode(const {'locals': {}, 'rules': []}),
      });
  await catalog.load();
  return catalog;
}

const _presets = UnifiedPresets(
  printers: [SlicerPreset(source: 'local', id: '1', name: 'Bambu Lab X2D')],
  processes: [SlicerPreset(source: 'local', id: '12', name: '0.20 mm Standard')],
  filaments: [SlicerPreset(source: 'local', id: '30', name: 'Bambu PLA Basic')],
);

/// Captures the slice request and reports the job as done immediately.
class _CapturingRepository extends SlicerRepository {
  _CapturingRepository() : super(Dio());

  Map<String, dynamic>? body;

  @override
  Future<int> sliceArchive(int archiveId, Map<String, dynamic> request) async {
    body = request;
    return 7;
  }

  @override
  Future<SliceJob> job(int jobId) async =>
      SliceJob.fromJson({'job_id': jobId, 'status': 'completed'});
}

void main() {
  late ProcessSchemaCatalog catalog;
  late _CapturingRepository repo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    catalog = await _catalog();
  });

  setUp(() => repo = _CapturingRepository());

  Future<void> openSheet(
    WidgetTester tester, {
    bool available = true,
    PresetValues presetValues = const PresetValues(resolved: true, reason: 'ok'),
    List<FilamentRequirement> requirements = const [],
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        slicerRepositoryProvider.overrideWithValue(repo),
        slicerPresetsProvider.overrideWith((ref) async => _presets),
        ownedPrinterCodesProvider.overrideWith((ref) async => const <String>{}),
        ownedFilamentsProvider
            .overrideWith((ref) async => const <OwnedFilament>[]),
        filamentRequirementsProvider.overrideWith((ref, arg) async => requirements),
        processSettingsAvailableProvider.overrideWith((ref) async => available),
        processSchemaProvider.overrideWith((ref) async => catalog),
        presetValuesProvider.overrideWith((ref, arg) async => presetValues),
      ],
      child: plApp(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSliceScreen(
                  context, const SliceTarget.archive(5, 'thing.3mf')),
              child: const Text('open'),
            ),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Slices and returns the captured body.
  ///
  /// Pumped by hand rather than settled: the progress dialog shows an
  /// indeterminate LinearProgressIndicator while the job runs, and an
  /// indeterminate animation never settles. A few frames are enough for the fake
  /// job to report itself terminal, which also cancels its poll timer.
  Future<Map<String, dynamic>> slice(WidgetTester tester) async {
    await tester.tap(find.text('Potnij'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return repo.body!;
  }

  group('the shape of the form', () {
    testWidgets('the plate is a plain row, not folded behind Advanced',
        (tester) async {
      // It was briefly collapsed together with the layout switches; the plate
      // and how objects land on it are basic choices, not expert ones, so they
      // sit in the list like everything else.
      await openSheet(tester);
      expect(find.text('Płyta robocza'), findsOneWidget);
      expect(find.text('Zaawansowane'), findsNothing);
    });

    testWidgets('the submit button is reachable without scrolling to it',
        (tester) async {
      // The reason this is a screen: as the last item of a scrolling sheet the
      // button sat below the fold on a multicolour file, and was clipped.
      await openSheet(tester, requirements: const [
        FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
        FilamentRequirement(slotId: 2, type: 'PETG', color: '#00FF00'),
        FilamentRequirement(slotId: 3, type: 'PETG', color: '#0000FF'),
      ]);
      // The form really is longer than the viewport — the last filament is
      // below the fold, which is what used to bury the button with it.
      expect(find.text('Filament 3'), findsNothing);
      // And the button is still tappable without a single scroll.
      final body = await slice(tester);
      expect(body['filament_presets'], hasLength(3));
    });
  });

  group('slots the plate does not use', () {
    testWidgets('are marked, and still pickable', (tester) async {
      // With full_slots the list covers every project slot, so a slot the plate
      // ignores still needs a preset — the slicer wants one per slot. Saying
      // which ones it ignores is what stops a hunt for the wrong spool.
      await openSheet(tester, requirements: const [
        FilamentRequirement(slotId: 1, type: 'PLA', usedInPlate: true),
        FilamentRequirement(slotId: 2, type: 'PETG', usedInPlate: false),
      ]);
      expect(find.text('Nieużywany na tej płycie'), findsOneWidget);
      expect(find.text('Filament 2'), findsOneWidget);

      // Every slot still reaches the request, positionally.
      final body = await slice(tester);
      expect(body['filament_presets'], hasLength(2));
    });

    testWidgets('are not marked when the server discriminated nothing',
        (tester) async {
      // Its own fallback flags every slot used, so all-true means either "all
      // used" or "could not tell" — marking then would claim knowledge nobody
      // has.
      await openSheet(tester, requirements: const [
        FilamentRequirement(slotId: 1, type: 'PLA', usedInPlate: true),
        FilamentRequirement(slotId: 2, type: 'PETG', usedInPlate: true),
      ]);
      expect(find.text('Nieużywany na tej płycie'), findsNothing);
    });
  });

  group('the entry point', () {
    testWidgets('is absent when the server or our assets cannot support it',
        (tester) async {
      // Absent rather than disabled: an older server drops process_overrides
      // without a word, so a control that appears to work is worse than none.
      await openSheet(tester, available: false);
      expect(find.text('Ustawienia procesu'), findsNothing);
    });

    testWidgets('shows the preset is untouched before anything is edited',
        (tester) async {
      await openSheet(tester);
      expect(find.text('Ustawienia procesu'), findsOneWidget);
      expect(find.text('Preset bez zmian'), findsOneWidget);
    });
  });

  group('the request body', () {
    testWidgets('carries no process_overrides key when nothing was edited',
        (tester) async {
      await openSheet(tester);
      final body = await slice(tester);
      expect(body.containsKey('process_overrides'), isFalse,
          reason: 'an untouched sheet must slice exactly as it did before');
      expect(body['printer_preset'], {'source': 'local', 'id': '1'});
    });

    testWidgets('carries the edits, serialised through the schema',
        (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('layer_height')),
              matching: find.byType(TextField)),
          '0.28');
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('sparse_infill_density')),
              matching: find.byType(TextField)),
          '25');
      await tester.pumpAndSettle();

      // Back out of the screen: the edits live in the sheet, so there is no
      // confirm step to press.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Zmienione: 2'), findsOneWidget);

      final body = await slice(tester);
      expect(body['process_overrides'], {
        'layer_height': '0.28',
        // The percent keeps its sign, which the bare field does not show.
        'sparse_infill_density': '25%',
      });
    });

    testWidgets('drops an edit that matches what the preset already says',
        (tester) async {
      await openSheet(tester,
          presetValues: const PresetValues(
              resolved: true, reason: 'ok', values: {'layer_height': '0.28'}));
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('layer_height')),
              matching: find.byType(TextField)),
          '0.28');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Preset bez zmian'), findsOneWidget);
      final body = await slice(tester);
      expect(body.containsKey('process_overrides'), isFalse,
          reason: 'an override equal to the preset is noise in the process JSON');
    });
  });
}
