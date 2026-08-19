import 'dart:convert';

import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/core/slicer/filament_slot_options.dart';
import 'package:bambuddy_mobile/core/slicer/process_schema_catalog.dart';
import 'package:bambuddy_mobile/features/slicer/process_settings_screen.dart';
import 'package:bambuddy_mobile/features/common/dash_search_field.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// A small stand-in for the 348-option catalog. Built through the loader's own
/// asset reader, so the real parsing path runs and the tests do not depend on
/// vendored data that a re-vendor is allowed to change.
///
/// `outer_wall_speed` is governed by a toggle rule over `wall_loops`, which is
/// what makes the greyed-out row reachable.
const _schema = {
  'layer_height': {
    'type': 'coFloat',
    'mode': 'simple',
    'label': 'Layer height',
    'tooltip': 'Slicing height for every layer.',
    'sidetext': 'mm',
    'min': 0.01,
    'max': 0.6,
    'default': 0.2,
  },
  'initial_layer_print_height': {
    'type': 'coFloat',
    'mode': 'advanced',
    'label': 'Initial layer height',
    'sidetext': 'mm',
    'default': 0.25,
  },
  'wall_loops': {
    'type': 'coInt',
    'mode': 'simple',
    'label': 'Wall loops',
    'default': 2,
  },
  'detect_thin_wall': {
    'type': 'coBool',
    'mode': 'expert',
    'label': 'Detect thin wall',
    'default': false,
  },
  'seam_position': {
    'type': 'coEnum',
    'mode': 'simple',
    'label': 'Seam position',
    'enum_values': ['aligned', 'nearest'],
    'enum_labels': ['Aligned', 'Nearest'],
    'default': 'aligned',
  },
  'outer_wall_speed': {
    'type': 'coFloat',
    'mode': 'simple',
    'label': 'Outer wall speed',
    'sidetext': 'mm/s',
    'default': 60,
  },
  'enable_support': {
    'type': 'coBool',
    'mode': 'simple',
    'label': 'Enable support',
    'default': false,
  },
  'support_filament': {
    'type': 'coInt',
    'mode': 'simple',
    'label': 'Support/raft base',
    'min': 0,
    'default': 0,
  },
  'support_interface_filament': {
    'type': 'coInt',
    'mode': 'simple',
    'label': 'Support/raft interface',
    'min': 0,
    'default': 0,
  },
  // Same kind of integer, deliberately not a slot picker — see
  // `filamentSlotOptionKeys`.
  'wipe_tower_filament': {
    'type': 'coInt',
    'mode': 'simple',
    'label': 'Wipe tower',
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
        'options': ['layer_height', 'initial_layer_print_height'],
      },
      {'group': 'Seam', 'options': ['seam_position']},
    ],
  },
  {
    'page': 'Strength',
    'groups': [
      {'group': 'Walls', 'options': ['wall_loops', 'detect_thin_wall']},
    ],
  },
  {
    'page': 'Speed',
    'groups': [
      {'group': 'Speeds', 'options': ['outer_wall_speed']},
    ],
  },
  {
    'page': 'Support',
    'groups': [
      {
        'group': 'Support filament',
        'options': [
          'enable_support',
          'support_filament',
          'support_interface_filament',
          'wipe_tower_filament',
        ],
      },
    ],
  },
];

const _toggles = {
  'locals': {
    'have_perimeters': 'config->opt_int("wall_loops") > 0',
    // The real local also ORs a raft; trimmed to the part these tests drive.
    'have_support_material': 'config->opt_bool("enable_support")',
  },
  'rules': [
    {'fields': ['outer_wall_speed'], 'enable_if': 'have_perimeters'},
    {
      'fields': ['support_interface_filament'],
      'enable_if': 'have_support_material',
    },
  ],
};

/// The text field belonging to one option. Necessary because `DropdownMenu`
/// renders a `TextField` of its own, so the enum rows and the search box all
/// answer to `find.byType(TextField)`.
Finder _fieldOf(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    );

final _searchBox = find.descendant(
  of: find.byType(DashSearchField),
  matching: find.byType(TextField),
);

/// The per-row revert button, by its tooltip: a `DropdownMenu` contributes an
/// `IconButton` of its own for the chevron.
Finder _revertOf(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byTooltip('Przywróć wartość z presetu'),
    );

Future<ProcessSchemaCatalog> _catalog() async {
  final catalog = ProcessSchemaCatalog(readAsset: (key) async => switch (key) {
        'assets/slicer/process-schema.json' => jsonEncode(_schema),
        'assets/slicer/process-ui-tree.json' => jsonEncode(_tree),
        _ => jsonEncode(_toggles),
      });
  await catalog.load();
  return catalog;
}

void main() {
  late List<Map<String, Object>> reported;

  /// Loaded once, here rather than inside a test: [ProcessSchemaCatalog.load]
  /// decodes in a `compute` isolate, and awaiting real async work inside
  /// `testWidgets` never completes — the binding runs on fake time.
  late ProcessSchemaCatalog catalog;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    catalog = await _catalog();
    expect(catalog.isLoaded, isTrue);
  });

  setUp(() => reported = []);

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> values = const {},
    PresetValues? presetValues = const PresetValues(resolved: true, reason: 'ok'),
    List<FilamentSlotChoice> filamentSlots = const [],
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        processSchemaProvider.overrideWith((ref) async => catalog),
        presetValuesProvider.overrideWith((ref, arg) async => presetValues),
      ],
      child: plApp(ProcessSettingsScreen(
        preset: const ('local', '12'),
        initialValues: values,
        onChanged: (next) => reported.add(next),
        filamentSlots: filamentSlots,
      )),
    ));
    await tester.pumpAndSettle();
  }

  group('mode filter', () {
    testWidgets('simple hides the advanced and expert options', (tester) async {
      await pump(tester);
      expect(find.text('Layer height'), findsWidgets);
      expect(find.text('Initial layer height'), findsNothing);
    });

    testWidgets('advanced reveals them without losing the simple ones',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Zaawansowane'));
      await tester.pumpAndSettle();
      expect(find.text('Layer height'), findsWidgets);
      expect(find.text('Initial layer height'), findsOneWidget);
    });
  });

  group('pages', () {
    testWidgets('one page at a time, switched by its chip', (tester) async {
      await pump(tester);
      expect(find.text('Wall loops'), findsNothing);
      await tester.tap(find.text('Strength'));
      await tester.pumpAndSettle();
      expect(find.text('Wall loops'), findsOneWidget);
      expect(find.text('Seam position'), findsNothing);
    });
  });

  group('search', () {
    testWidgets('spans every page and drops the page selector', (tester) async {
      await pump(tester);
      // "Outer wall speed" lives on a page that is not showing.
      expect(find.text('Outer wall speed'), findsNothing);
      await tester.enterText(_searchBox, 'wall');
      await tester.pumpAndSettle();
      expect(find.text('Wall loops'), findsOneWidget);
      expect(find.text('Outer wall speed'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Strength'), findsNothing);
    });

    testWidgets('a space matches an underscore in the key', (tester) async {
      await pump(tester);
      await tester.enterText(_searchBox, 'outer wall speed');
      await tester.pumpAndSettle();
      expect(find.text('Outer wall speed'), findsOneWidget);
      expect(find.text('Layer height'), findsNothing);
    });

    testWidgets('the group name is searchable, not just the label',
        (tester) async {
      await pump(tester);
      await tester.enterText(_searchBox, 'seam');
      await tester.pumpAndSettle();
      expect(find.text('Seam position'), findsOneWidget);
    });

    testWidgets('nothing matching says so', (tester) async {
      await pump(tester);
      await tester.enterText(_searchBox, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Żadne ustawienie nie pasuje do zapytania.'),
          findsOneWidget);
    });
  });

  group('rules', () {
    testWidgets('a setting the slicer ignores is shown, greyed, not editable',
        (tester) async {
      // wall_loops 0 turns have_perimeters false, which disables outer_wall_speed.
      await pump(tester, values: {'wall_loops': '0'});
      await tester.enterText(_searchBox, 'outer wall speed');
      await tester.pumpAndSettle();

      expect(find.text('Outer wall speed'), findsOneWidget,
          reason: 'a missing row would read as a missing feature');
      expect(tester.widget<TextField>(_fieldOf('outer_wall_speed')).enabled,
          isFalse);
      expect(find.text('Przy obecnych ustawieniach slicer to pomija.'),
          findsOneWidget);
    });

    testWidgets('it becomes editable once the dependency is back',
        (tester) async {
      await pump(tester, values: {'wall_loops': '2'});
      await tester.enterText(_searchBox, 'outer wall speed');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_fieldOf('outer_wall_speed')).enabled,
          isTrue);
    });
  });

  group('editing', () {
    testWidgets('a typed value is reported upward', (tester) async {
      await pump(tester);
      await tester.enterText(_fieldOf('layer_height'), '0.28');
      await tester.pumpAndSettle();
      expect(reported.last['layer_height'], '0.28');
    });

    testWidgets('a switch reports a bool, not a string', (tester) async {
      // detect_thin_wall is expert and lives on the Strength page.
      await pump(tester);
      await tester.tap(find.text('Eksperckie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strength'));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('detect_thin_wall')),
          matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      // A bool, not '1': the codec spells it for the wire, the state stays typed.
      expect(reported.last['detect_thin_wall'], isTrue);
    });

    testWidgets('reverting an enum whose preset value is not a listed option',
        (tester) async {
      // A preset can hold a value the vendored schema does not declare, so the
      // dropdown starts blank. Picking and then reverting has to go back to
      // blank: leaving the old label up would show a setting the slice will not
      // use.
      await pump(
        tester,
        presetValues: const PresetValues(
            resolved: true,
            reason: 'ok',
            values: {'seam_position': 'some_unlisted_mode'}),
      );
      String shown() => tester
          .widget<TextField>(_fieldOf('seam_position'))
          .controller!
          .text;
      expect(shown(), isEmpty);

      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('seam_position')),
          matching: find.byType(DropdownMenu<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nearest').last);
      await tester.pumpAndSettle();
      expect(shown(), 'Nearest');

      await tester.tap(_revertOf('seam_position'));
      await tester.pumpAndSettle();
      expect(reported.last, isEmpty);
      expect(shown(), isEmpty);
    });

    testWidgets('an enum reports the wire value, not its label', (tester) async {
      await pump(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('seam_position')),
          matching: find.byType(DropdownMenu<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nearest').last);
      await tester.pumpAndSettle();
      expect(reported.last['seam_position'], 'nearest');
    });
  });

  group('reverting', () {
    testWidgets('nothing changed offers no reset', (tester) async {
      await pump(tester);
      expect(find.textContaining('Przywróć'), findsNothing);
    });

    testWidgets('a change offers a counted reset that clears everything',
        (tester) async {
      await pump(tester, values: {'layer_height': '0.28'});
      expect(find.text('Przywróć 1'), findsOneWidget);

      await tester.tap(find.text('Przywróć 1'));
      await tester.pumpAndSettle();

      expect(reported.last, isEmpty);
      expect(find.text('Przywróć 1'), findsNothing);
    });

    testWidgets('a value equal to the preset is not counted as a change',
        (tester) async {
      // The whole reason preset values are fetched: matching what the preset
      // already says is not an override.
      await pump(
        tester,
        values: {'layer_height': '0.28'},
        presetValues: const PresetValues(
            resolved: true, reason: 'ok', values: {'layer_height': '0.28'}),
      );
      expect(find.textContaining('Przywróć'), findsNothing);
    });
  });

  group('when the preset values could not be read', () {
    testWidgets('an outdated sidecar is named, and the screen still works',
        (tester) async {
      await pump(tester,
          presetValues:
              const PresetValues(resolved: false, reason: 'sidecar_outdated'));
      expect(find.textContaining('kontener slicera jest starszy'),
          findsOneWidget);
      expect(find.text('Layer height'), findsWidgets);
    });

    testWidgets('a missing sidecar config gets its own wording',
        (tester) async {
      await pump(tester,
          presetValues:
              const PresetValues(resolved: false, reason: 'not_configured'));
      expect(find.textContaining('żaden kontener slicera nie jest'),
          findsOneWidget);
    });

    testWidgets('a resolved read shows no notice at all', (tester) async {
      await pump(tester);
      expect(find.textContaining('Pokazujemy wartości domyślne'), findsNothing);
    });
  });

  group('filament-slot options', () {
    const slots = [
      FilamentSlotChoice(slot: 1, label: 'Bambu PLA Basic'),
      FilamentSlotChoice(slot: 2, label: 'Bambu Support for PLA'),
    ];
    const defaultLabel = 'Domyślny (filament danego obszaru)';

    Future<void> openSupport(WidgetTester tester) async {
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
    }

    Finder dropdownOf(String key) => find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(DropdownMenu<String>),
        );

    /// What the closed control displays.
    String shown(WidgetTester tester, String key) =>
        tester.widget<TextField>(_fieldOf(key)).controller!.text;

    Future<void> openMenu(WidgetTester tester, String key) async {
      await tester.tap(dropdownOf(key));
      await tester.pumpAndSettle();
    }

    testWidgets('offer the picked filaments by name', (tester) async {
      await pump(tester, filamentSlots: slots);
      await openSupport(tester);
      await openMenu(tester, 'support_filament');

      expect(find.text(defaultLabel), findsWidgets);
      expect(find.text('1: Bambu PLA Basic'), findsWidgets);
      expect(find.text('2: Bambu Support for PLA'), findsWidgets);
    });

    testWidgets("start on the slicer's 0, meaning no specific filament",
        (tester) async {
      await pump(tester, filamentSlots: slots);
      await openSupport(tester);
      expect(shown(tester, 'support_filament'), defaultLabel);
    });

    testWidgets('report the slot index, spelled as the number field spells it',
        (tester) async {
      // A string, not an int: the control it replaces emits strings, and the
      // codec downstream must not be able to tell which one produced the edit.
      await pump(tester, filamentSlots: slots);
      await openSupport(tester);
      await openMenu(tester, 'support_filament');
      await tester.tap(find.text('2: Bambu Support for PLA').last);
      await tester.pumpAndSettle();

      expect(reported.last['support_filament'], '2');
    });

    testWidgets('stay a plain number field when no filaments are known',
        (tester) async {
      // An STL source has no slot list; an empty dropdown would be worse than
      // the field it replaced.
      await pump(tester);
      await openSupport(tester);
      expect(dropdownOf('support_filament'), findsNothing);
      expect(_fieldOf('support_filament'), findsOneWidget);
    });

    testWidgets('obey the slicer\'s own gating like every other row',
        (tester) async {
      // support_interface_filament sits behind have_support_material. Becoming a
      // dropdown must not exempt it from the rules.
      await pump(tester, filamentSlots: slots);
      await openSupport(tester);
      expect(
          tester
              .widget<DropdownMenu<String>>(
                  dropdownOf('support_interface_filament'))
              .enabled,
          isFalse);

      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('enable_support')),
          matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<DropdownMenu<String>>(
                  dropdownOf('support_interface_filament'))
              .enabled,
          isTrue);
    });

    testWidgets('mark a slot the plate does not consume', (tester) async {
      await pump(tester, filamentSlots: const [
        FilamentSlotChoice(slot: 1, label: 'Bambu PLA Basic'),
        FilamentSlotChoice(
            slot: 2, label: 'Bambu Support for PLA', unused: true),
      ]);
      await openSupport(tester);
      await openMenu(tester, 'support_filament');

      expect(find.textContaining('Nieużywany na tej płycie'), findsWidgets);
    });

    testWidgets('show a slot this file does not have rather than nothing',
        (tester) async {
      // The preset can name slot 5 on a two-slot file. Leaving the control blank
      // would hide the one value worth seeing.
      await pump(
        tester,
        filamentSlots: slots,
        presetValues: const PresetValues(
            resolved: true, reason: 'ok', values: {'support_filament': '5'}),
      );
      await openSupport(tester);
      expect(shown(tester, 'support_filament'),
          'Slot 5 — ten plik nie ma takiego slotu');
    });

    testWidgets('leave the control blank on a value that is not a slot at all',
        (tester) async {
      // Malformed rather than out of range: a slot named "" would be an
      // invention, so nothing is claimed.
      await pump(
        tester,
        filamentSlots: slots,
        presetValues: const PresetValues(
            resolved: true, reason: 'ok', values: {'support_filament': ''}),
      );
      await openSupport(tester);
      expect(shown(tester, 'support_filament'), isEmpty);
      expect(find.textContaining('Slot'), findsNothing);
    });

    testWidgets('revert goes back to the default, not to the last pick',
        (tester) async {
      // The enum control had exactly this bug: `DropdownMenu` re-applies
      // `initialSelection` only when it changes identity.
      await pump(tester, filamentSlots: slots);
      await openSupport(tester);
      await openMenu(tester, 'support_filament');
      await tester.tap(find.text('1: Bambu PLA Basic').last);
      await tester.pumpAndSettle();
      expect(shown(tester, 'support_filament'), '1: Bambu PLA Basic');

      await tester.tap(_revertOf('support_filament'));
      await tester.pumpAndSettle();

      expect(reported.last, isEmpty);
      expect(shown(tester, 'support_filament'), defaultLabel);
    });

    testWidgets('the wipe tower keeps its number field', (tester) async {
      // Same kind of integer, different meaning for 0: "whichever is available,
      // preferring non-soluble" is not "the region's own filament".
      await pump(tester, filamentSlots: slots);
      await openSupport(tester);
      expect(dropdownOf('wipe_tower_filament'), findsNothing);
      expect(_fieldOf('wipe_tower_filament'), findsOneWidget);
    });
  });

  testWidgets('no values at all means the screen has nothing to offer',
      (tester) async {
    // Only reachable as a race: the entry point gates on the same read.
    await pump(tester, presetValues: null);
    expect(
        find.textContaining('nie potrafi podać ustawień procesu'), findsOneWidget);
  });
}
