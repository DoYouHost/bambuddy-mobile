import 'dart:convert';

import 'package:bambuddy_mobile/core/models/embedded_settings.dart';
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
  'support_filament': {
    'type': 'coInt',
    'mode': 'simple',
    'label': 'Support/raft base',
    'min': 0,
    'default': 0,
  },
};

const _tree = [
  {
    'page': 'Quality',
    'groups': [
      {
        'group': 'Layer height',
        'options': ['layer_height', 'sparse_infill_density', 'support_filament'],
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
    EmbeddedSettings embedded = EmbeddedSettings.none,
    UnifiedPresets presets = _presets,
    bool layoutOptions = false,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        slicerRepositoryProvider.overrideWithValue(repo),
        slicerPresetsProvider.overrideWith((ref) async => presets),
        embeddedSettingsProvider.overrideWith((ref, arg) async => embedded),
        sliceLayoutOptionsProvider.overrideWith((ref) async => layoutOptions),
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

    testWidgets('carries a filament slot as the index the slicer stores',
        (tester) async {
      // The form's own picks are what name the slots in there, so this proves the
      // whole path: pick → label → index → body.
      await openSheet(tester, requirements: const [
        FilamentRequirement(slotId: 1, type: 'PLA', usedInPlate: true),
        FilamentRequirement(slotId: 2, type: 'PETG', usedInPlate: false),
      ]);
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('support_filament')),
          matching: find.byType(DropdownMenu<String>)));
      await tester.pumpAndSettle();

      // Named after the preset the form auto-picked, not "1" and "2"; and the
      // slot the plate ignores says so here too.
      expect(find.textContaining('1: Bambu PLA Basic'), findsWidgets);
      expect(find.textContaining('Nieużywany na tej płycie'), findsWidgets);

      await tester.tap(find.textContaining('2: Bambu PLA Basic').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      final body = await slice(tester);
      expect(body['process_overrides'], {'support_filament': '2'});
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

  group('slice as designed', () {
    const designed = EmbeddedSettings(
      printer: 'Bambu Lab X2D',
      process: '0.20mm Standard @BBL X2D',
      serverSupportsAsDesigned: true,
    );

    testWidgets('is absent while the server cannot honour it', (tester) async {
      // Absent rather than disabled, for the same reason the layout switches
      // are: nothing rejects the field, so a switch that looks live and slices
      // by the profile anyway is worse than no switch.
      await openSheet(tester,
          embedded: const EmbeddedSettings(
            printer: 'Bambu Lab X2D',
            process: '0.20mm Standard @BBL X2D',
            serverSupportsAsDesigned: false,
          ));
      expect(find.text('Użyj ustawień z pliku'), findsNothing);
    });

    testWidgets('is absent for a file with no embedded profile', (tester) async {
      await openSheet(tester);
      expect(find.text('Użyj ustawień z pliku'), findsNothing);
    });

    testWidgets('is absent while the picked printer is a different model',
        (tester) async {
      // The design's printer is not among the offered ones, so the form keeps
      // its own default and the offer never applies — honouring another
      // printer's embedded settings would lay the model out for the wrong bed.
      await openSheet(tester,
          embedded: const EmbeddedSettings(
            printer: 'Bambu Lab P1S 0.4 nozzle',
            process: '0.20mm Standard @BBL P1S',
            serverSupportsAsDesigned: true,
          ));
      expect(find.text('Użyj ustawień z pliku'), findsNothing);
    });

    testWidgets('defaults the printer to the one the file was designed for',
        (tester) async {
      // Without this the switch is unreachable in practice: the user would have
      // to guess which printer makes the offer appear.
      await openSheet(
        tester,
        embedded: designed,
        presets: const UnifiedPresets(
          printers: [
            SlicerPreset(source: 'local', id: '2', name: 'Bambu Lab A1'),
            SlicerPreset(source: 'local', id: '1', name: 'Bambu Lab X2D'),
          ],
          processes: [
            SlicerPreset(source: 'local', id: '12', name: '0.20 mm Standard')
          ],
          filaments: [
            SlicerPreset(source: 'local', id: '30', name: 'Bambu PLA Basic')
          ],
        ),
      );

      expect(find.text('Użyj ustawień z pliku'), findsOneWidget);
      final body = await slice(tester);
      expect(body['printer_preset'], {'source': 'local', 'id': '1'},
          reason: 'the design\'s printer, not the first in the list');
    });

    testWidgets('sends the field, and nothing the file overrules',
        (tester) async {
      await openSheet(tester, embedded: designed);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      expect(find.text('Nieużywane — decyduje plik'), findsWidgets);

      final body = await slice(tester);
      expect(body['use_embedded_settings'], isTrue);
      // Still required by the server's validator on this path, and ignored
      // there — so they stay in the body.
      expect(body['printer_preset'], {'source': 'local', 'id': '1'});
      expect(body['process_preset'], {'source': 'local', 'id': '12'});
      expect(body['filament_preset'], {'source': 'local', 'id': '30'});
    });

    testWidgets('locks every control the profiles drive', (tester) async {
      await openSheet(tester, embedded: designed);
      ListTile tile(String label) => tester.widget<ListTile>(find.ancestor(
          of: find.text(label), matching: find.byType(ListTile)));

      expect(tile('Drukarka').enabled, isTrue);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      // The printer among them: moving off the design's target would drop the
      // gate and take the switch with it.
      expect(tile('Drukarka').enabled, isFalse);
      expect(tile('Proces / Jakość').enabled, isFalse);
      expect(tile('Płyta robocza').enabled, isFalse);
      expect(tile('Ustawienia procesu').enabled, isFalse);
      expect(tile('Filament').enabled, isFalse);
    });

    testWidgets('dims a locked row, and drops its chevron', (tester) async {
      // ListTile.enabled alone barely reads on the dark theme — the row still
      // looked tappable, which is what a live emulator showed.
      await openSheet(tester, embedded: designed);
      double dimOf(String label) => tester
          .widgetList<Opacity>(
              find.ancestor(of: find.text(label), matching: find.byType(Opacity)))
          .map((o) => o.opacity)
          .fold(1.0, (a, b) => a * b);
      int chevronsIn(String label) => tester
          .widgetList<Icon>(find.descendant(
              of: find.ancestor(
                  of: find.text(label), matching: find.byType(ListTile)),
              matching: find.byIcon(Icons.chevron_right)))
          .length;

      expect(dimOf('Drukarka'), 1.0);
      expect(chevronsIn('Drukarka'), 1);

      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      expect(dimOf('Drukarka'), lessThan(0.6));
      expect(dimOf('Płyta robocza'), lessThan(0.6));
      expect(chevronsIn('Drukarka'), 0);
      expect(chevronsIn('Płyta robocza'), 0);
    });

    testWidgets('drops a build plate that was picked before it was turned on',
        (tester) async {
      // bed_type patches a process JSON the embedded path never builds, so
      // sending it would only misreport what this slice did.
      await openSheet(tester, embedded: designed);
      await tester.tap(find.text('Płyta robocza'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Textured PEI Plate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      expect((await slice(tester)).containsKey('bed_type'), isFalse);
    });

    testWidgets('keeps the plate when it is turned off again', (tester) async {
      // The other half of the case above, or the assertion proves nothing: an
      // absent key is also what an untouched picker produces.
      await openSheet(tester, embedded: designed);
      await tester.tap(find.text('Płyta robocza'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Textured PEI Plate'));
      await tester.pumpAndSettle();

      expect((await slice(tester))['bed_type'], 'Textured PEI Plate');
    });

    testWidgets('drops process overrides that were edited before it was on',
        (tester) async {
      await openSheet(tester, embedded: designed);
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

      // Recorded while off — the same edit reaches the body in the group above.
      expect(find.text('Zmienione: 1'), findsOneWidget);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      expect((await slice(tester)).containsKey('process_overrides'), isFalse);
    });

    testWidgets('leaves a filament slot nothing could fill still pickable',
        (tester) async {
      // The validator wants a ref per slot on this path too, so locking an
      // empty slot would dead-end the form: unsubmittable and unfixable.
      await openSheet(
        tester,
        embedded: designed,
        presets: const UnifiedPresets(
          printers: [SlicerPreset(source: 'local', id: '1', name: 'Bambu Lab X2D')],
          processes: [SlicerPreset(source: 'local', id: '12', name: '0.20 mm')],
          filaments: [],
        ),
      );
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      final filament = tester.widget<ListTile>(find.ancestor(
          of: find.text('Filament'), matching: find.byType(ListTile)));
      expect(filament.enabled, isTrue);
    });

    testWidgets('leaves the layout switches live', (tester) async {
      // They act on the geometry through the CLI, not through the process
      // config, so they work whatever the settings come from.
      await openSheet(tester, embedded: designed, layoutOptions: true);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatyczna orientacja'));
      await tester.pumpAndSettle();

      final body = await slice(tester);
      expect(body['use_embedded_settings'], isTrue);
      expect(body['auto_orient'], isTrue);
    });

    testWidgets('turned off again slices by the profile as before',
        (tester) async {
      await openSheet(tester, embedded: designed);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      final body = await slice(tester);
      expect(body.containsKey('use_embedded_settings'), isFalse,
          reason: 'the default path must stay byte-identical to before');
    });
  });
}
