import 'dart:async';

import 'dart:convert';

import 'package:bambuddy_mobile/core/models/embedded_settings.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/loaded_spools.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/slice_job.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/core/slicer/process_schema_catalog.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ams_slot_config_providers.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        'options': [
          'layer_height',
          'sparse_infill_density',
          'support_filament',
        ],
      },
    ],
  },
];

Future<ProcessSchemaCatalog> _catalog() async {
  final catalog = ProcessSchemaCatalog(
    readAsset: (key) async => switch (key) {
      'assets/slicer/process-schema.json' => jsonEncode(_schema),
      'assets/slicer/process-ui-tree.json' => jsonEncode(_tree),
      _ => jsonEncode(const {'locals': {}, 'rules': []}),
    },
  );
  await catalog.load();
  return catalog;
}

const _presets = UnifiedPresets(
  printers: [SlicerPreset(source: 'local', id: '1', name: 'Bambu Lab X2D')],
  processes: [
    SlicerPreset(source: 'local', id: '12', name: '0.20 mm Standard'),
  ],
  filaments: [SlicerPreset(source: 'local', id: '30', name: 'Bambu PLA Basic')],
);

/// Captures the slice request and reports the job as done immediately.
class _CapturingRepository extends SlicerRepository {
  _CapturingRepository() : super(Dio());

  Map<String, dynamic>? body;

  /// What the finished job reports back, as the server's `SliceResponse`.
  Map<String, dynamic> result = const {
    'library_file_id': 9,
    'name': 'out.gcode.3mf',
  };

  @override
  Future<int> sliceArchive(int archiveId, Map<String, dynamic> request) async {
    body = request;
    return 7;
  }

  @override
  Future<SliceJob> job(int jobId) async => SliceJob.fromJson({
    'job_id': jobId,
    'status': 'completed',
    'result': result,
  });
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
    PresetValues presetValues = const PresetValues(
      resolved: true,
      reason: 'ok',
    ),
    List<FilamentRequirement> requirements = const [],
    EmbeddedSettings embedded = EmbeddedSettings.none,
    UnifiedPresets presets = _presets,
    bool layoutOptions = false,
    Set<String> ownedCodes = const {},
    List<SlicerPipeline> pipelines = const [],
    bool pipelinesSupported = false,
    List<OwnedFilament> owned = const [],
    Future<UnifiedPresets>? heldPresets,
    void Function()? onSchemaLoad,
    List<LoadedSpoolPrinter>? loaded,
    Duration loadedAfter = Duration.zero,
    Map<String, String> registry = const {},
    Map<String, Object> prefs = const {},
    PlateList plates = PlateList.none,
    List<int>? requirementPlates,
    Map<int, List<FilamentRequirement>> requirementsByPlate = const {},
    Duration requirementsAfter = Duration.zero,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSliceScreen(
                context,
                const SliceTarget.archive(5, 'thing.3mf'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      overrides: [
        slicerRepositoryProvider.overrideWithValue(repo),
        slicerPresetsProvider.overrideWith(
          (ref) => heldPresets ?? Future.value(presets),
        ),
        embeddedSettingsProvider.overrideWith((ref, arg) async => embedded),
        sliceLayoutOptionsProvider.overrideWithValue(AsyncData(layoutOptions)),
        ownedPrinterCodesProvider.overrideWith((ref) async => ownedCodes),
        ownedFilamentsProvider.overrideWith((ref) async => owned),
        ownedSpoolFacetsProvider.overrideWith(
          (ref) async =>
              (materials: const <String>{}, brands: const <String>{}),
        ),
        filamentRequirementsProvider.overrideWith((ref, arg) async {
          requirementPlates?.add(arg.plate);
          final byPlate = requirementsByPlate[arg.plate];
          if (byPlate == null) return requirements;
          await Future<void>.delayed(requirementsAfter);
          return byPlate;
        }),
        plateListProvider.overrideWith((ref, arg) async => plates),
        // With [onSchemaLoad] the availability gate is the real one, so the
        // test can see when the screen makes it decode the schema.
        if (onSchemaLoad == null)
          processSettingsAvailableProvider.overrideWithValue(
            AsyncData(available),
          )
        else
          processOverridesProvider.overrideWithValue(const AsyncData(true)),
        processSchemaProvider.overrideWith((ref) async {
          onSchemaLoad?.call();
          return catalog;
        }),
        presetValuesProvider.overrideWith((ref, arg) async => presetValues),
        // Inert by default: without these the bar probes the pipeline routes
        // over a real Dio and leaves a hanging timer, the same trap as
        // [inertFirmwareOverride].
        pipelinesSupportedProvider.overrideWithValue(
          AsyncData(pipelinesSupported),
        ),
        pipelinesProvider.overrideWith((ref) async => pipelines),
        // Reaches `currentUserProvider` and the repository's observed latch,
        // neither of which these tests stand up.
        canWritePipelinesProvider.overrideWithValue(const AsyncData(true)),
        // Null by default: a server without #3172, so no filters at all.
        loadedSpoolsProvider.overrideWith((ref) async {
          await Future<void>.delayed(loadedAfter);
          return loaded;
        }),
        printerModelRegistryProvider.overrideWith((ref) async => registry),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    await tester.tap(find.text('open'));
    if (heldPresets != null) {
      // A spinner is up while they load, and it never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
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

  testWidgets('the process schema decodes while the presets still load', (
    tester,
  ) async {
    // The card it gates is built only once the presets are in; asked from
    // there, the decode began after that wait instead of during it.
    final presets = Completer<UnifiedPresets>();
    var decoding = false;
    await openSheet(
      tester,
      heldPresets: presets.future,
      onSchemaLoad: () => decoding = true,
    );

    expect(decoding, isTrue);

    // One frame, not a settle: the card has to be in the frame the presets
    // arrive in, or it still lands after the form and pushes it down.
    presets.complete(_presets);
    await tester.pump();
    expect(byLogId('slice.process_settings'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  group('the shape of the form', () {
    testWidgets('the plate is a plain row, not folded behind Advanced', (
      tester,
    ) async {
      // It was briefly collapsed together with the layout switches; the plate
      // and how objects land on it are basic choices, not expert ones, so they
      // sit in the list like everything else.
      await openSheet(tester);
      expect(find.text('Płyta robocza'), findsOneWidget);
      expect(find.text('Zaawansowane'), findsNothing);
    });

    testWidgets('the submit button is reachable without scrolling to it', (
      tester,
    ) async {
      // The reason this is a screen: as the last item of a scrolling sheet the
      // button sat below the fold on a multicolour file, and was clipped.
      await openSheet(
        tester,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
          FilamentRequirement(slotId: 2, type: 'PETG', color: '#00FF00'),
          FilamentRequirement(slotId: 3, type: 'PETG', color: '#0000FF'),
        ],
      );
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
      await openSheet(
        tester,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', usedInPlate: true),
          FilamentRequirement(slotId: 2, type: 'PETG', usedInPlate: false),
        ],
      );
      expect(find.text('Nieużywany na tej płycie'), findsOneWidget);
      expect(find.text('Filament 2'), findsOneWidget);

      // Every slot still reaches the request, positionally.
      final body = await slice(tester);
      expect(body['filament_presets'], hasLength(2));
    });

    testWidgets('are not marked when the server discriminated nothing', (
      tester,
    ) async {
      // Its own fallback flags every slot used, so all-true means either "all
      // used" or "could not tell" — marking then would claim knowledge nobody
      // has.
      await openSheet(
        tester,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', usedInPlate: true),
          FilamentRequirement(slotId: 2, type: 'PETG', usedInPlate: true),
        ],
      );
      expect(find.text('Nieużywany na tej płycie'), findsNothing);
    });
  });

  group('the entry point', () {
    testWidgets('is absent when the server or our assets cannot support it', (
      tester,
    ) async {
      // Absent rather than disabled: an older server drops process_overrides
      // without a word, so a control that appears to work is worse than none.
      await openSheet(tester, available: false);
      expect(find.text('Ustawienia procesu'), findsNothing);
    });

    testWidgets('shows the preset is untouched before anything is edited', (
      tester,
    ) async {
      await openSheet(tester);
      expect(find.text('Ustawienia procesu'), findsOneWidget);
      expect(find.text('Preset bez zmian'), findsOneWidget);
    });
  });

  group('the request body', () {
    testWidgets('carries no process_overrides key when nothing was edited', (
      tester,
    ) async {
      await openSheet(tester);
      final body = await slice(tester);
      expect(
        body.containsKey('process_overrides'),
        isFalse,
        reason: 'an untouched sheet must slice exactly as it did before',
      );
      expect(body['printer_preset'], {'source': 'local', 'id': '1'});
    });

    testWidgets('carries the edits, serialised through the schema', (
      tester,
    ) async {
      await openSheet(tester);
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('layer_height')),
          matching: find.byType(TextField),
        ),
        '0.28',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('sparse_infill_density')),
          matching: find.byType(TextField),
        ),
        '25',
      );
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

    testWidgets('carries a filament slot as the index the slicer stores', (
      tester,
    ) async {
      // The form's own picks are what name the slots in there, so this proves the
      // whole path: pick → label → index → body.
      await openSheet(
        tester,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', usedInPlate: true),
          FilamentRequirement(slotId: 2, type: 'PETG', usedInPlate: false),
        ],
      );
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('support_filament')),
          matching: find.byType(DropdownMenu<String>),
        ),
      );
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

    testWidgets('drops an edit that matches what the preset already says', (
      tester,
    ) async {
      await openSheet(
        tester,
        presetValues: const PresetValues(
          resolved: true,
          reason: 'ok',
          values: {'layer_height': '0.28'},
        ),
      );
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('layer_height')),
          matching: find.byType(TextField),
        ),
        '0.28',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Preset bez zmian'), findsOneWidget);
      final body = await slice(tester);
      expect(
        body.containsKey('process_overrides'),
        isFalse,
        reason: 'an override equal to the preset is noise in the process JSON',
      );
    });
  });

  group('the colour each slot prints in', () {
    // Without it the slicer writes its compiled-in green onto every slot, and
    // the print dialog then reports a colour mismatch against the AMS slot the
    // print was mapped to (server #2977).
    const shelf = [
      (name: 'Bambu PLA Basic', material: 'PLA', color: 'ff0000ff'),
      (name: 'Bambu PLA Basic', material: 'PLA', color: '0000ffff'),
    ];

    testWidgets('reaches the body as the picked spool colour', (tester) async {
      await openSheet(
        tester,
        owned: shelf,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', color: '#0000FF'),
        ],
      );
      final body = await slice(tester);
      expect(body['filament_colours'], ['#0000FF']);
    });

    testWidgets('is absent when the inventory names no colour', (tester) async {
      // Nothing to say: the request has to stay identical to one from before
      // the field existed, so the server's own fallback chain still runs.
      await openSheet(tester);
      final body = await slice(tester);
      expect(body.containsKey('filament_colours'), isFalse);
    });
  });

  group('the printer a file was designed for', () {
    // The case that makes the note necessary: the design targets a printer the
    // user does not own, so it is filtered out of the offered list and the
    // switch would otherwise live behind the picker's "all presets" toggle.
    const foreign = EmbeddedSettings(
      printer: 'Bambu Lab X1 Carbon 0.4 nozzle',
      process: '0.20mm Standard @BBL X1C',
      serverSupportsAsDesigned: true,
    );
    const catalog = UnifiedPresets(
      printers: [
        SlicerPreset(
          source: 'local',
          id: '1',
          name: 'Bambu Lab X2D 0.4 nozzle',
        ),
        SlicerPreset(
          source: 'standard',
          id: '9',
          name: 'Bambu Lab X1 Carbon 0.4 nozzle',
        ),
      ],
      processes: [SlicerPreset(source: 'local', id: '12', name: '0.20 mm')],
      filaments: [SlicerPreset(source: 'local', id: '30', name: 'Bambu PLA')],
    );

    Future<void> open(
      WidgetTester tester, {
      EmbeddedSettings embedded = foreign,
      UnifiedPresets presets = catalog,
    }) => openSheet(
      tester,
      embedded: embedded,
      presets: presets,
      ownedCodes: const {'X2D'},
    );

    testWidgets('is named on the printer row when it is not the picked one', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Plik jest pod X1 Carbon 0.4'), findsOneWidget);
      expect(find.text('Użyj ustawień z pliku'), findsNothing);
    });

    testWidgets('switches to it, which is what reveals the switch', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Przełącz'));
      await tester.pumpAndSettle();

      expect(find.text('Bambu Lab X1 Carbon 0.4 nozzle'), findsWidgets);
      expect(find.text('Użyj ustawień z pliku'), findsOneWidget);
      expect(
        find.text('Plik jest pod X1 Carbon 0.4'),
        findsNothing,
        reason: 'nothing left to point at once it is the picked printer',
      );
    });

    testWidgets('offers the action as a button, not as a word in a sentence', (
      tester,
    ) async {
      // It started as a tappable fragment at the end of the sentence, which the
      // printer's name pushed onto a line of its own — an orphan "·" that read
      // as a rendering fault, with a tap target the size of the words.
      await open(tester);
      final size = tester.getSize(
        find.widgetWithText(FilledButton, 'Przełącz'),
      );

      expect(size.height, greaterThanOrEqualTo(36));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('is named without an action when no preset matches it', (
      tester,
    ) async {
      // Knowing what the file wants is worth something even when there is
      // nothing to switch to; an action that cannot work is not.
      await open(tester, presets: _presets);

      expect(find.text('Plik jest pod X1 Carbon 0.4'), findsOneWidget);
      expect(find.text('Przełącz'), findsNothing);
    });

    testWidgets('says nothing when the file names no printer', (tester) async {
      await open(tester, embedded: EmbeddedSettings.none);
      expect(find.textContaining('Plik jest pod'), findsNothing);
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
      await openSheet(
        tester,
        embedded: const EmbeddedSettings(
          printer: 'Bambu Lab X2D',
          process: '0.20mm Standard @BBL X2D',
          serverSupportsAsDesigned: false,
        ),
      );
      expect(find.text('Użyj ustawień z pliku'), findsNothing);
    });

    testWidgets('is absent for a file with no embedded profile', (
      tester,
    ) async {
      await openSheet(tester);
      expect(find.text('Użyj ustawień z pliku'), findsNothing);
    });

    testWidgets('is absent while the picked printer is a different model', (
      tester,
    ) async {
      // The design's printer is not among the offered ones, so the form keeps
      // its own default and the offer never applies — honouring another
      // printer's embedded settings would lay the model out for the wrong bed.
      await openSheet(
        tester,
        embedded: const EmbeddedSettings(
          printer: 'Bambu Lab P1S 0.4 nozzle',
          process: '0.20mm Standard @BBL P1S',
          serverSupportsAsDesigned: true,
        ),
      );
      expect(find.text('Użyj ustawień z pliku'), findsNothing);
    });

    testWidgets('defaults the printer to the one the file was designed for', (
      tester,
    ) async {
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
            SlicerPreset(source: 'local', id: '12', name: '0.20 mm Standard'),
          ],
          filaments: [
            SlicerPreset(source: 'local', id: '30', name: 'Bambu PLA Basic'),
          ],
        ),
      );

      expect(find.text('Użyj ustawień z pliku'), findsOneWidget);
      final body = await slice(tester);
      expect(
        body['printer_preset'],
        {'source': 'local', 'id': '1'},
        reason: 'the design\'s printer, not the first in the list',
      );
    });

    testWidgets('sends the field, and nothing the file overrules', (
      tester,
    ) async {
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
      ListTile tile(String label) => tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );

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

    testWidgets('cannot have the printer changed under it', (tester) async {
      // Why the flag needs no reset on a printer change: there is no way to
      // make one. The row does not open, so a switch left on cannot be carried
      // to a printer the design does not target.
      await openSheet(tester, embedded: designed);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drukarka'));
      await tester.pumpAndSettle();

      expect(
        find.text('Szukaj profili'),
        findsNothing,
        reason: 'the preset picker must not have opened',
      );
    });

    testWidgets('dims a locked row, and drops its chevron', (tester) async {
      // ListTile.enabled alone barely reads on the dark theme — the row still
      // looked tappable, which is what a live emulator showed.
      await openSheet(tester, embedded: designed);
      double dimOf(String label) => tester
          .widgetList<Opacity>(
            find.ancestor(of: find.text(label), matching: find.byType(Opacity)),
          )
          .map((o) => o.opacity)
          .fold(1.0, (a, b) => a * b);
      int chevronsIn(String label) => tester
          .widgetList<Icon>(
            find.descendant(
              of: find.ancestor(
                of: find.text(label),
                matching: find.byType(ListTile),
              ),
              matching: find.byIcon(Icons.chevron_right),
            ),
          )
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

    testWidgets('drops a build plate that was picked before it was turned on', (
      tester,
    ) async {
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

    testWidgets('drops process overrides that were edited before it was on', (
      tester,
    ) async {
      await openSheet(tester, embedded: designed);
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('layer_height')),
          matching: find.byType(TextField),
        ),
        '0.28',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Recorded while off — the same edit reaches the body in the group above.
      expect(find.text('Zmienione: 1'), findsOneWidget);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      expect((await slice(tester)).containsKey('process_overrides'), isFalse);
    });

    testWidgets('leaves a filament slot nothing could fill still pickable', (
      tester,
    ) async {
      // The validator wants a ref per slot on this path too, so locking an
      // empty slot would dead-end the form: unsubmittable and unfixable.
      await openSheet(
        tester,
        embedded: designed,
        presets: const UnifiedPresets(
          printers: [
            SlicerPreset(source: 'local', id: '1', name: 'Bambu Lab X2D'),
          ],
          processes: [SlicerPreset(source: 'local', id: '12', name: '0.20 mm')],
          filaments: [],
        ),
      );
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      final filament = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Filament'),
          matching: find.byType(ListTile),
        ),
      );
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

    testWidgets('turned off again slices by the profile as before', (
      tester,
    ) async {
      await openSheet(tester, embedded: designed);
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Użyj ustawień z pliku'));
      await tester.pumpAndSettle();

      final body = await slice(tester);
      expect(
        body.containsKey('use_embedded_settings'),
        isFalse,
        reason: 'the default path must stay byte-identical to before',
      );
    });
  });

  group('applying a pipeline', () {
    const bundle = SlicerPipeline(
      id: 3,
      name: 'X2D Gridfinity PETG',
      printerPreset: PresetRef(source: 'local', id: '1'),
      processPreset: PresetRef(source: 'local', id: '99'),
      filamentPresets: [PresetRef(source: 'local', id: '31')],
      bedType: 'Engineering Plate',
    );

    /// A catalog that can actually resolve [bundle] — the presets the default
    /// `_presets` lacks.
    const catalogWithBundle = UnifiedPresets(
      printers: [SlicerPreset(source: 'local', id: '1', name: 'Bambu Lab X2D')],
      processes: [
        SlicerPreset(source: 'local', id: '12', name: '0.20 mm Standard'),
        SlicerPreset(source: 'local', id: '99', name: '0.30 mm Gridfinity'),
      ],
      filaments: [
        SlicerPreset(source: 'local', id: '30', name: 'Bambu PLA Basic'),
        SlicerPreset(source: 'local', id: '31', name: 'Bambu PETG HF'),
      ],
    );

    Future<void> apply(WidgetTester tester) async {
      await tester.tap(find.text('Zastosuj pipeline…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('X2D Gridfinity PETG').last);
      await tester.pumpAndSettle();
      // The "applied" SnackBar sits over the submit button, and its display
      // window is a Timer rather than an animation — so `pumpAndSettle` returns
      // with it still up. Wait it out, or the slice tap lands on the toast.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    /// The form is a lazy `ListView`, and the pipeline card pushed the filament
    /// rows past the fold — off-screen children are never built, so a finder
    /// would report them missing whatever the state says. Scrolls them in.
    Future<void> revealSlots(WidgetTester tester) async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    testWidgets('the row is absent on a server without the routes', (
      tester,
    ) async {
      // Older servers 404 the whole feature, and an API-key session is refused
      // it — a control that can only fail is worse than none.
      await openSheet(tester, pipelines: const [bundle]);
      expect(find.text('Pipeline'), findsNothing);
    });

    testWidgets('fills every slot from one pick', (tester) async {
      await openSheet(
        tester,
        presets: catalogWithBundle,
        pipelines: const [bundle],
        pipelinesSupported: true,
      );
      await apply(tester);
      await revealSlots(tester);

      expect(find.text('0.30 mm Gridfinity'), findsOneWidget);
      expect(find.text('Bambu PETG HF'), findsOneWidget);
      expect(find.text('Engineering Plate'), findsOneWidget);

      final body = await slice(tester);
      expect(body['printer_preset'], {'source': 'local', 'id': '1'});
      expect(body['process_preset'], {'source': 'local', 'id': '99'});
      expect(body['filament_preset'], {'source': 'local', 'id': '31'});
      expect(body['bed_type'], 'Engineering Plate');
    });

    testWidgets('does not clear the slots it just filled', (tester) async {
      // Picking a printer normally wipes the process and filaments, because
      // they were chosen for the old one. A pipeline supplies all four at once,
      // so routing it through that reset would undo the pick.
      await openSheet(
        tester,
        presets: catalogWithBundle,
        pipelines: const [bundle],
        pipelinesSupported: true,
      );
      await apply(tester);
      await revealSlots(tester);

      expect(find.text('Dotknij, aby wybrać'), findsNothing);
    });

    testWidgets('a shorter pipeline leaves the slots it does not reach', (
      tester,
    ) async {
      // `filament_presets` is positional, so entry i only ever lands on slot i
      // and the tail keeps whatever was auto-picked for it.
      await openSheet(
        tester,
        presets: catalogWithBundle,
        pipelines: const [bundle],
        pipelinesSupported: true,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PETG', color: '#00FF00'),
          FilamentRequirement(slotId: 2, type: 'PLA', color: '#FF0000'),
        ],
      );
      await apply(tester);
      await revealSlots(tester);

      expect(find.text('Bambu PETG HF'), findsOneWidget);
      expect(
        find.text('Bambu PLA Basic'),
        findsOneWidget,
        reason: 'slot 2 is beyond the pipeline and must keep its own pick',
      );

      final body = await slice(tester);
      expect(body['filament_presets'], [
        {'source': 'local', 'id': '31'},
        {'source': 'local', 'id': '30'},
      ]);
    });

    testWidgets('a preset this catalog does not list still reaches the request', (
      tester,
    ) async {
      // A pipeline outlives the preset list it was saved from, and a cloud tier
      // that failed to load empties whole slots. Dropping the ref would rewrite
      // the user's pipeline silently on the next slice.
      await openSheet(
        tester,
        presets: _presets, // knows neither process 99 nor filament 31
        pipelines: const [bundle],
        pipelinesSupported: true,
      );
      await apply(tester);
      await revealSlots(tester);

      expect(find.text('Nie ma go już w katalogu'), findsWidgets);

      final body = await slice(tester);
      expect(body['process_preset'], {'source': 'local', 'id': '99'});
      expect(body['filament_preset'], {'source': 'local', 'id': '31'});
    });
  });

  group('where the sliced file landed', () {
    /// The result dialog's text, read through the localization API rather than
    /// spelled out — the harness runs in Polish.
    AppLocalizations l10n(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(AlertDialog)));

    testWidgets('a file filed somewhere else says so, and why', (tester) async {
      // The slice succeeded; it just did not land in the external folder the
      // source lives in. Silence here is what made #2810 unreproducible from
      // the UI: the row appears in the right folder, the file never arrives.
      repo.result = const {
        'library_file_id': 9,
        'name': 'out.gcode.3mf',
        'external_write_fallback': 'external_readonly',
      };
      await openSheet(tester);
      await slice(tester);

      expect(
        find.text(
          '${l10n(tester).sliceExternalFallback} '
          '${l10n(tester).sliceExternalReadonly}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('every reason the server can send has a sentence', (
      tester,
    ) async {
      // The five `_resolve_slice_destination` returns (library.py). A reason
      // the app knows but has no clause for reads as the generic half alone,
      // which is indistinguishable from a reason it has never heard of.
      for (final reason in const [
        'external_readonly',
        'external_no_path',
        'external_unreachable',
        'external_not_writable',
        'external_invalid_name',
      ]) {
        repo.result = {
          'library_file_id': 9,
          'name': 'out.gcode.3mf',
          'external_write_fallback': reason,
        };
        await openSheet(tester);
        await slice(tester);

        expect(
          find.text(l10n(tester).sliceExternalFallback),
          findsNothing,
          reason: '$reason rendered without a reason clause',
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a reason this build has no sentence for still says where', (
      tester,
    ) async {
      // A newer server may name a reason this app does not know. The half that
      // matters — where the file is — must not depend on recognizing it.
      repo.result = const {
        'library_file_id': 9,
        'name': 'out.gcode.3mf',
        'external_write_fallback': 'external_something_new',
      };
      await openSheet(tester);
      await slice(tester);

      expect(find.text(l10n(tester).sliceExternalFallback), findsOneWidget);
    });

    testWidgets('a normal slice says nothing about folders', (tester) async {
      // Null on every ordinary slice, and on every server older than 1.2.5.4.
      await openSheet(tester);
      await slice(tester);

      expect(
        find.textContaining(l10n(tester).sliceExternalFallback),
        findsNothing,
      );
    });
  });

  group('online printers and loaded spools (#3172)', () {
    const registry = {'Bambu Lab X1 Carbon': 'X1C', 'Bambu Lab H2D': 'H2D'};
    const x1c = SlicerPreset(
      source: 'standard',
      id: 'x1c',
      name: 'Bambu Lab X1 Carbon 0.4 nozzle',
    );
    const h2d = SlicerPreset(
      source: 'standard',
      id: 'h2d',
      name: 'Bambu Lab H2D 0.4 nozzle',
    );
    const generic = SlicerPreset(
      source: 'standard',
      id: 'generic',
      name: 'Generic PLA @BBL H2D',
      filamentType: 'PLA',
    );
    const basic = SlicerPreset(
      source: 'standard',
      id: 'basic',
      name: 'Bambu PLA Basic @BBL H2D',
      filamentType: 'PLA',
    );
    const presets = UnifiedPresets(
      printers: [x1c, h2d],
      processes: [
        SlicerPreset(source: 'standard', id: 'p', name: '0.20mm Standard'),
      ],
      filaments: [generic, basic],
    );
    const online = [
      LoadedSpoolPrinter(
        id: 1,
        name: 'H2D one',
        model: 'H2D',
        ams: [
          LoadedSpoolUnit(
            id: 0,
            isAmsHt: false,
            trays: [
              LoadedSpoolTray(
                amsId: 0,
                trayId: 0,
                trayType: 'PLA',
                traySubBrands: 'PLA Basic',
                trayInfoIdx: 'GFA00',
                trayColor: 'FF8800FF',
              ),
            ],
          ),
        ],
      ),
    ];

    Future<void> open(
      WidgetTester tester, {
      List<LoadedSpoolPrinter>? loaded = online,
      bool onlyOnline = false,
      bool onlyLoaded = false,
    }) => openSheet(
      tester,
      presets: presets,
      loaded: loaded,
      registry: registry,
      prefs: {
        'slice_only_online_printers': onlyOnline,
        'slice_only_loaded_spools': onlyLoaded,
      },
    );

    testWidgets('a server without the route offers no filters', (tester) async {
      await open(tester, loaded: null);
      expect(byLogId('slice.only_online'), findsNothing);
      expect(byLogId('slice.only_loaded'), findsNothing);
    });

    testWidgets('both start off and change nothing', (tester) async {
      await open(tester);
      expect(byLogId('slice.only_online'), findsOneWidget);
      final body = await slice(tester);
      expect(body['printer_preset'], x1c.toRef());
      expect(body['filament_preset'], generic.toRef());
    });

    testWidgets('only online printers moves the auto-pick to an online model', (
      tester,
    ) async {
      await open(tester, onlyOnline: true);
      expect((await slice(tester))['printer_preset'], h2d.toRef());
    });

    testWidgets('an answer that lands after the form moves its auto-pick', (
      tester,
    ) async {
      await openSheet(
        tester,
        presets: presets,
        loaded: online,
        loadedAfter: const Duration(seconds: 1),
        registry: registry,
        prefs: {'slice_only_online_printers': true},
      );
      expect(find.text(x1c.name), findsOneWidget, reason: 'nothing known yet');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect((await slice(tester))['printer_preset'], h2d.toRef());
    });

    testWidgets('a row the user filled survives the move to an online model', (
      tester,
    ) async {
      await openSheet(
        tester,
        presets: presets,
        loaded: online,
        // Long enough for the two sheets to open and close before it lands.
        loadedAfter: const Duration(seconds: 30),
        registry: registry,
        prefs: {'slice_only_online_printers': true},
      );
      await tester.tap(find.text(generic.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(basic.name));
      await tester.pumpAndSettle();

      expect(find.text(x1c.name), findsOneWidget, reason: 'not moved yet');
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      final body = await slice(tester);
      expect(body['printer_preset'], h2d.toRef());
      expect(body['filament_preset'], basic.toRef());
    });

    testWidgets('a row made for the old printer does not survive the move', (
      tester,
    ) async {
      const forX1c = SlicerPreset(
        source: 'standard',
        id: 'x1c-pla',
        name: 'Generic PLA @BBL X1C',
        filamentType: 'PLA',
      );
      await openSheet(
        tester,
        presets: const UnifiedPresets(
          printers: [x1c, h2d],
          processes: [
            SlicerPreset(source: 'standard', id: 'p', name: '0.20mm Standard'),
          ],
          filaments: [generic, forX1c],
        ),
        loaded: online,
        loadedAfter: const Duration(seconds: 30),
        registry: registry,
        prefs: {'slice_only_online_printers': true},
      );
      // On the X1C the H2D profile is ruled out, so the X1C one is the
      // auto-pick; choosing it again makes it the user's own pick.
      await tester.tap(find.text(forX1c.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(forX1c.name).last);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      final body = await slice(tester);
      expect(body['printer_preset'], h2d.toRef());
      expect(body['filament_preset'], generic.toRef());
    });

    testWidgets('a process for another printer is not the auto-pick, even '
        'an imported one', (tester) async {
      // The web's rule: an imported preset is ruled out by its own
      // `compatible_printers`, not kept for being imported.
      const forH2d = SlicerPreset(
        source: 'local',
        id: 'h2d-proc',
        name: 'My 0.20mm',
        compatiblePrinters: ['Bambu Lab H2D 0.4 nozzle'],
      );
      const untagged = SlicerPreset(
        source: 'standard',
        id: 'any',
        name: '0.20mm Standard',
      );
      await openSheet(
        tester,
        presets: const UnifiedPresets(
          printers: [x1c],
          processes: [forH2d, untagged],
          filaments: [basic],
        ),
        registry: registry,
        loaded: const [],
      );

      final body = await slice(tester);
      expect(body['process_preset'], untagged.toRef());
    });

    testWidgets('when every process is for another printer the list is not '
        'left empty', (tester) async {
      const forH2d = SlicerPreset(
        source: 'standard',
        id: 'h2d-proc',
        name: '0.20mm Standard @BBL H2D',
      );
      await openSheet(
        tester,
        presets: const UnifiedPresets(
          printers: [x1c],
          processes: [forH2d],
          filaments: [basic],
        ),
        registry: registry,
        loaded: const [],
      );

      final body = await slice(tester);
      expect(body['process_preset'], forH2d.toRef());
    });

    testWidgets('the move stays among the printers the user owns', (
      tester,
    ) async {
      // The H2D is online but none of the user's: the form keeps to the
      // owned list it offers, as the designed-printer default does.
      await openSheet(
        tester,
        presets: presets,
        loaded: online,
        loadedAfter: const Duration(seconds: 1),
        registry: registry,
        ownedCodes: const {'X1C'},
        prefs: {'slice_only_online_printers': true},
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(x1c.name), findsOneWidget);
      expect(find.text(h2d.name), findsNothing);
    });

    testWidgets('a loaded spool of the slot\'s material wins over the first', (
      tester,
    ) async {
      const petg = SlicerPreset(
        source: 'standard',
        id: 'petg',
        name: 'Generic PETG @BBL H2D',
        filamentType: 'PETG',
      );
      await openSheet(
        tester,
        presets: const UnifiedPresets(
          printers: [x1c, h2d],
          processes: [
            SlicerPreset(source: 'standard', id: 'p', name: '0.20mm Standard'),
          ],
          filaments: [generic, basic, petg],
        ),
        registry: registry,
        requirements: const [FilamentRequirement(slotId: 1, type: 'PETG')],
        prefs: {
          'slice_only_online_printers': true,
          'slice_only_loaded_spools': true,
        },
        loaded: const [
          LoadedSpoolPrinter(
            id: 1,
            name: 'H2D one',
            model: 'H2D',
            ams: [
              LoadedSpoolUnit(
                id: 0,
                isAmsHt: false,
                trays: [
                  LoadedSpoolTray(
                    amsId: 0,
                    trayId: 0,
                    trayType: 'PLA',
                    traySubBrands: 'PLA Basic',
                    trayInfoIdx: 'GFA00',
                  ),
                  LoadedSpoolTray(
                    amsId: 0,
                    trayId: 1,
                    trayType: 'PETG',
                    trayInfoIdx: 'GFG99',
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      expect((await slice(tester))['filament_preset'], petg.toRef());
    });

    testWidgets('only loaded spools auto-picks the spool in the AMS', (
      tester,
    ) async {
      await open(tester, onlyOnline: true, onlyLoaded: true);
      expect((await slice(tester))['filament_preset'], basic.toRef());
    });

    testWidgets('with nothing online it says the lists stay whole', (
      tester,
    ) async {
      await open(tester, loaded: const [], onlyOnline: true);
      final l10n = lookupAppLocalizations(const Locale('pl'));
      expect(find.text(l10n.sliceNoneOnline), findsOneWidget);
      expect((await slice(tester))['printer_preset'], x1c.toRef());
    });

    final l10n = lookupAppLocalizations(const Locale('pl'));

    /// Opens the filament row's sheet. The row sits below the fold once the
    /// filters are on screen.
    Future<void> openFilament(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text(l10n.sliceFilament),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.sliceFilament));
      await tester.pumpAndSettle();
    }

    testWidgets('the row opens on the spools, and a spool fills it and its '
        'colour', (tester) async {
      // On the H2D: the X1C the form starts on has no printer online.
      await open(tester, onlyOnline: true);
      await openFilament(tester);
      expect(byLogId('slice.filament_tab'), findsOneWidget);
      await tester.tap(byLogId('slice.spool_tile'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.sliceSpoolFrom('H2D one · A1')), findsOneWidget);
      final body = await slice(tester);
      expect(body['filament_preset'], basic.toRef());
      expect(body['filament_colours'], ['#FF8800']);
    });

    testWidgets('a profile picked from the other tab drops the spool', (
      tester,
    ) async {
      await open(tester, onlyOnline: true);
      await openFilament(tester);
      await tester.tap(byLogId('slice.spool_tile'));
      await tester.pumpAndSettle();
      await openFilament(tester);
      await tester.tap(find.text(l10n.sliceTabProfiles));
      await tester.pumpAndSettle();
      await tester.tap(find.text(generic.name).last);
      await tester.pumpAndSettle();

      expect(find.textContaining('H2D one · A1'), findsNothing);
      final body = await slice(tester);
      expect(body['filament_preset'], generic.toRef());
      expect(body.containsKey('filament_colours'), isFalse);
    });

    testWidgets('slots that cannot be picked are one compact line', (
      tester,
    ) async {
      await openSheet(
        tester,
        presets: presets,
        registry: registry,
        prefs: {'slice_only_online_printers': true},
        loaded: const [
          LoadedSpoolPrinter(
            id: 1,
            name: 'H2D one',
            model: 'H2D',
            ams: [
              LoadedSpoolUnit(
                id: 0,
                isAmsHt: false,
                trays: [
                  LoadedSpoolTray(
                    amsId: 0,
                    trayId: 0,
                    trayType: 'PA-CF',
                    traySubBrands: 'Odd brand',
                  ),
                  LoadedSpoolTray(amsId: 0, trayId: 1, exists: false),
                ],
              ),
            ],
          ),
        ],
      );
      await openFilament(tester);
      expect(byLogId('slice.spool_tile'), findsNothing);
      expect(find.text(l10n.sliceSpoolsUnavailable), findsOneWidget);
      expect(
        find.text('A1 · PA-CF · ${l10n.sliceSpoolNoProfileShort}'),
        findsOneWidget,
      );
      expect(find.text('A2 · ${l10n.sliceSpoolEmpty}'), findsOneWidget);
    });

    testWidgets('the spools tab says when no printer of the model is online', (
      tester,
    ) async {
      await open(tester);
      await openFilament(tester);
      expect(find.text(l10n.sliceLoadedNoneOfModel), findsOneWidget);
    });

    testWidgets('the sheet lists every owned printer\'s presets, starting '
        'on the selected one', (tester) async {
      const forX1c = SlicerPreset(
        source: 'standard',
        id: 'x1c-pla',
        name: 'Generic PLA @BBL X1C',
        filamentType: 'PLA',
      );
      await openSheet(
        tester,
        presets: const UnifiedPresets(
          printers: [h2d, x1c],
          processes: [
            SlicerPreset(source: 'standard', id: 'p', name: '0.20mm Standard'),
          ],
          filaments: [generic, forX1c],
        ),
        registry: registry,
        ownedCodes: const {'H2D', 'X1C'},
        loaded: const [],
      );
      await openFilament(tester);
      expect(find.text(forX1c.name), findsNothing, reason: 'starts on H2D');
      await tester.tap(find.widgetWithText(ChoiceChip, 'X1C'));
      await tester.pumpAndSettle();
      expect(find.text(forX1c.name), findsOneWidget);
    });

    testWidgets('with nothing online the sheet is the profile list alone', (
      tester,
    ) async {
      await open(tester, loaded: const []);
      await openFilament(tester);
      expect(byLogId('slice.filament_tab'), findsNothing);
      expect(byLogId('slice.preset_option'), findsWidgets);
    });

    testWidgets('a switch is remembered on the device', (tester) async {
      await open(tester);
      await tester.tap(byLogId('slice.only_loaded'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('slice_only_loaded_spools'), isTrue);
    });
  });

  group('which plate to slice', () {
    const twoPlates = PlateList(
      plates: [
        PlateInfo(index: 1, name: 'Body'),
        PlateInfo(index: 2, name: 'Lid'),
      ],
    );
    final l10n = lookupAppLocalizations(const Locale('pl'));

    testWidgets('a single-plate source names no plate', (tester) async {
      await openSheet(tester);
      expect(byLogId('slice.plate'), findsNothing);
      expect((await slice(tester)).containsKey('plate'), isFalse);
    });

    testWidgets('a multi-plate source slices plate 1 until told otherwise', (
      tester,
    ) async {
      await openSheet(tester, plates: twoPlates);
      expect(byLogId('slice.plate'), findsOneWidget);
      expect(
        (await slice(tester)).containsKey('plate'),
        isFalse,
        reason: 'plate 1 is what the sidecar slices with none named',
      );
    });

    testWidgets('another plate is sliced, with its own slots', (tester) async {
      final asked = <int>[];
      await openSheet(tester, plates: twoPlates, requirementPlates: asked);
      await tester.tap(byLogId('slice.plate'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Lid'));
      await tester.pumpAndSettle();

      expect(asked, contains(2), reason: 'the slots are read for plate 2');
      expect((await slice(tester))['plate'], 2);
    });

    testWidgets('all plates slice as plate 0, every slot in use', (
      tester,
    ) async {
      await openSheet(
        tester,
        plates: twoPlates,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA'),
          FilamentRequirement(slotId: 2, type: 'PLA', usedInPlate: false),
        ],
      );
      // The second row sits below the fold with the plate card above it.
      await tester.scrollUntilVisible(
        find.text(l10n.sliceFilamentUnused),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        byLogId('slice.all_plates'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(byLogId('slice.all_plates'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(l10n.sliceFilamentNumbered('2')),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text(l10n.sliceFilamentUnused), findsNothing);
      expect(find.text(l10n.sliceAllPlates(2)), findsWidgets);
      await tester.tap(find.text(l10n.sliceAllPlates(2)).last);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(repo.body!['plate'], 0);
    });

    testWidgets('a new plate\'s rows wait for its slots', (tester) async {
      const tpu = SlicerPreset(
        source: 'local',
        id: '31',
        name: 'Generic TPU',
        filamentType: 'TPU',
      );
      await openSheet(
        tester,
        plates: twoPlates,
        presets: const UnifiedPresets(
          printers: [
            SlicerPreset(source: 'local', id: '1', name: 'Bambu Lab X2D'),
          ],
          processes: [
            SlicerPreset(source: 'local', id: '12', name: '0.20 mm Standard'),
          ],
          filaments: [
            SlicerPreset(source: 'local', id: '30', name: 'Bambu PLA Basic'),
            tpu,
          ],
        ),
        owned: const [(name: 'Generic TPU', material: 'TPU', color: null)],
        requirementsByPlate: const {
          2: [
            FilamentRequirement(slotId: 1, type: 'TPU'),
            FilamentRequirement(slotId: 2, type: 'PLA'),
          ],
        },
        requirementsAfter: const Duration(seconds: 5),
      );
      await tester.tap(byLogId('slice.plate'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Lid'));
      await tester.pump();

      final submit = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Potnij'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(submit.onPressed, isNull, reason: 'no slots, no slice yet');

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final body = await slice(tester);
      expect((body['filament_presets'] as List).first, tpu.toRef());
    });

    testWidgets('a slot edit is dropped with the plate it named', (
      tester,
    ) async {
      await openSheet(
        tester,
        plates: twoPlates,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA'),
          FilamentRequirement(slotId: 2, type: 'PETG'),
        ],
      );
      await tester.tap(find.text('Ustawienia procesu'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('support_filament')),
          matching: find.byType(DropdownMenu<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('2: Bambu PLA Basic').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(byLogId('slice.plate'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Lid'));
      await tester.pumpAndSettle();

      expect((await slice(tester)).containsKey('process_overrides'), isFalse);
    });
  });
}
