import 'dart:async';
import 'dart:convert';

import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/profile_default.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/core/models/spool_preset_override.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/profile_defaults_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ams_slot_config_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// "Use as default" and the prefill in the new-spool form (server #1326).
///
/// The profile-default calls run through the real repository over a scripted
/// server, so what these tests count and record is what leaves the phone. The
/// spool's own write is the fake notifier's, as in `spool_model_presets_test`.
class _FakeInventory extends InventoryNotifier {
  final List<String> writes = [];

  @override
  Future<InventoryState> build() async => InventoryState(spools: []);

  @override
  Future<Spool?> createSpool(SpoolDraft draft) async {
    writes.add('create');
    return const Spool(id: 9, material: 'PLA');
  }
}

class _MockRepo extends Mock implements InventoryRepository {}

const _resolvePath = '/api/v1/inventory/profile-defaults/resolve';
const _listPath = '/api/v1/inventory/profile-defaults';

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// What the server answers for a product; null is "no default".
typedef _Resolver = Map<String, dynamic>? Function(ProfileProduct product);

Map<String, dynamic> _basic({String? preset}) => {
  'slicer_filament': 'GFA00',
  'slicer_filament_name': preset ?? 'Bambu PLA Basic',
  'presets': [
    {
      'printer_model': 'X1C',
      'nozzle_diameter': '',
      'slicer_filament': 'GFA00_X1C',
      'slicer_filament_name': 'Bambu PLA Basic @BBL X1C',
    },
  ],
  'k_profiles': [],
  'default_ids': [1],
};

Map<String, dynamic> _stored(
  int id, {
  String color = '',
  List<Map<String, dynamic>> k = const [],
}) => {
  'id': id,
  'brand': '',
  'material': 'PLA',
  'subtype': '',
  'color_name': color,
  'slicer_filament': 'GFA00',
  'slicer_filament_name': 'Bambu PLA Basic',
  'presets': [],
  'k_profiles': k,
  'updated_at': '2026-10-30T10:00:00',
};

void main() {
  setUpAll(() {
    registerFallbackValue(const <SpoolPresetOverride>[]);
  });

  late ScriptedAdapter server;
  late _FakeInventory inventory;

  Finder materialField() => find.descendant(
    of: find.byType(DropdownMenu<String>).first,
    matching: find.byType(TextField),
  );
  Finder brandField() => find.descendant(
    of: find.widgetWithText(DropdownMenu<String>, pl.inventoryFieldBrand),
    matching: find.byType(TextField),
  );
  Finder colorField() =>
      find.widgetWithText(TextFormField, pl.inventoryFieldColorName);
  Finder saveButton() => find.widgetWithText(FilledButton, pl.inventorySave);
  Finder defaultSwitch() => find.byType(SwitchListTile);

  Future<void> afterTyping(WidgetTester tester) async {
    // The lookup waits for the typing to stop.
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
  }

  Future<void> typeCombo(WidgetTester tester, Finder field, String text) async {
    await tester.enterText(field, text);
    // Typing into a combo opens its menu, which covers the sheet until closed.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await afterTyping(tester);
  }

  Future<void> typeField(WidgetTester tester, Finder field, String text) async {
    await tester.enterText(field, text);
    await afterTyping(tester);
  }

  /// Opens the new-spool form on a server that answers [resolver] and lists
  /// [stored]; the scope is the form's own window, tall enough to build it all.
  Future<void> openForm(
    WidgetTester tester, {
    bool supported = true,
    _Resolver? resolver,
    List<Map<String, dynamic>> stored = const [],
    int resolveStatus = 200,
    bool Function(ProfileProduct product)? failFor,
    Completer<void>? gate,
    bool Function(ProfileProduct product)? holdWhen,
    int putStatus = 200,
    double textScale = 1,
    List<SlicerPreset> presets = const [],
  }) async {
    usePhoneWindow(tester, dp: 2600);
    inventory = _FakeInventory();
    server = ScriptedAdapter((o) {
      if (o.path == _resolvePath) {
        final q = o.queryParameters;
        final product = ProfileProduct(
          material: '${q['material']}',
          brand: '${q['brand']}',
          subtype: '${q['subtype']}',
          colorName: '${q['color_name']}',
        );
        if (resolveStatus != 200 || (failFor?.call(product) ?? false)) {
          return _json({
            'detail': 'boom',
          }, resolveStatus == 200 ? 500 : resolveStatus);
        }
        final answer = (resolver ?? (_) => null)(product);
        if (gate != null && (holdWhen?.call(product) ?? false)) {
          // The body arrives only when the test says so.
          return ResponseBody(
            Stream.fromFuture(
              gate.future.then(
                (_) => Uint8List.fromList(utf8.encode(jsonEncode(answer))),
              ),
            ),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return _json(answer);
      }
      if (o.path == _listPath && o.method == 'GET') return _json(stored);
      if (o.path == _listPath && o.method == 'PUT') {
        if (putStatus != 200) return _json({'detail': 'no'}, putStatus);
        return _json({..._stored(5), ...(o.data as Map<String, dynamic>)});
      }
      return _json({'detail': 'Not Found'}, 404);
    });
    final dio = testDio()..httpClientAdapter = server;
    final repo = _MockRepo();
    when(() => repo.savePresetOverrides(any(), any())).thenAnswer((_) async {});
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openSpoolForm(context),
            child: const Text('open'),
          ),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      overrides: [
        inventoryProvider.overrideWith(() => inventory),
        inventoryRepositoryProvider.overrideWithValue(repo),
        noServerProfileOverride,
        presetOverridesSupportedProvider.overrideWithValue(
          const AsyncData(true),
        ),
        profileDefaultsSupportedProvider.overrideWithValue(
          AsyncData(supported),
        ),
        profileDefaultsRepositoryProvider.overrideWithValue(
          ProfileDefaultsRepository(dio, () async => InventoryBackend.native),
        ),
        printerModelsProvider.overrideWith((_) async => const ['X1C']),
        slicerPresetsProvider.overrideWith(
          (_) async => UnifiedPresets(
            printers: const [],
            processes: const [],
            filaments: presets,
          ),
        ),
        printerModelRegistryProvider.overrideWith(
          (_) async => const {'Bambu Lab X1C': 'X1C'},
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  List<String> calls() => [
    for (final r in server.requests) '${r.method} ${r.path}',
  ];
  List<String> lookups() => [
    for (final r in server.requests)
      if (r.path == _resolvePath) '${r.queryParameters['material']}',
  ];

  group('prefill', () {
    testWidgets('fills the preset and the model rows from the default of the '
        'typed product', (tester) async {
      await openForm(tester, resolver: (_) => _basic());

      await typeCombo(tester, materialField(), 'PLA');

      expect(find.text('Bambu PLA Basic'), findsOneWidget);
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);
      expect(
        find.text(pl.inventoryProfileDefaultPrefilled('PLA')),
        findsOneWidget,
      );
      expect(server.requests.last.queryParameters, {
        'material': 'PLA',
        'brand': '',
        'subtype': '',
        'color_name': '',
      });
    });

    testWidgets('says nothing for a product without a default', (tester) async {
      await openForm(tester);

      await typeCombo(tester, materialField(), 'PLA');

      expect(find.text(pl.inventoryPrinterPresetsHint), findsOneWidget);
      expect(
        find.textContaining(pl.inventoryProfileDefaultPrefilled('')),
        findsNothing,
      );
      expect(find.text(pl.inventoryPrinterPresetDefault), findsOneWidget);
    });

    testWidgets('a lookup is not made without a material, and not twice '
        'for the same product', (tester) async {
      await openForm(tester, resolver: (_) => _basic());

      await typeCombo(tester, brandField(), 'Bambu Lab');
      expect(lookups(), isEmpty);

      await typeCombo(tester, materialField(), 'PLA');
      // Same product again, as a cursor move or a re-selection reports it.
      await typeCombo(tester, materialField(), ' pla ');

      expect(lookups(), ['PLA']);
    });

    testWidgets('the next product\'s default replaces the previous one\'s, '
        'and a row the user picked stays', (tester) async {
      await openForm(
        tester,
        resolver: (p) => switch (p.brand) {
          'Acme' => {
            'slicer_filament': 'ACME',
            'slicer_filament_name': 'Acme PLA',
            'presets': [
              {
                'printer_model': 'X1C',
                'nozzle_diameter': '',
                'slicer_filament': 'ACME_X1C',
                'slicer_filament_name': 'Acme PLA @BBL X1C',
              },
            ],
          },
          _ => _basic(),
        },
      );
      await typeCombo(tester, materialField(), 'PLA');
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);

      await typeCombo(tester, brandField(), 'Acme');

      expect(find.text('Acme PLA @BBL X1C'), findsOneWidget);
      expect(find.text('Acme PLA'), findsOneWidget);
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsNothing);
      expect(find.text('Bambu PLA Basic'), findsNothing);
    });

    testWidgets('the default of a product without one takes its own out', (
      tester,
    ) async {
      await openForm(
        tester,
        resolver: (p) => p.brand.isEmpty ? _basic() : null,
      );
      await typeCombo(tester, materialField(), 'PLA');
      expect(find.text('Bambu PLA Basic'), findsOneWidget);

      await typeCombo(tester, brandField(), 'Nobody');

      expect(find.text('Bambu PLA Basic'), findsNothing);
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsNothing);
      expect(
        find.text(pl.inventoryProfileDefaultPrefilled('Nobody PLA')),
        findsNothing,
      );
    });

    testWidgets('a preset the user picked is not replaced by the default\'s', (
      tester,
    ) async {
      await openForm(
        tester,
        resolver: (_) => _basic(),
        presets: const [
          SlicerPreset(
            source: 'cloud',
            id: 'MINE',
            name: 'My own PLA',
            filamentType: 'PLA',
          ),
        ],
      );

      await tester.tap(find.text(pl.inventorySlicerPresetNone));
      await settle(tester);
      await tester.tap(find.text('My own PLA'));
      await settle(tester);
      await typeCombo(tester, materialField(), 'PLA');

      expect(find.text('My own PLA'), findsOneWidget);
      expect(find.text('Bambu PLA Basic'), findsNothing);
      // The model rows are still the default's: only the preset was the user's.
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);
    });

    testWidgets('an answer for what was typed a moment ago does not land on '
        'top of what is typed now', (tester) async {
      final gate = Completer<void>();
      await openForm(
        tester,
        resolver: (p) => p.brand.isEmpty ? _basic() : null,
        gate: gate,
        holdWhen: (p) => p.brand.isEmpty,
      );
      await typeCombo(tester, materialField(), 'PLA');
      // The lookup for PLA is in flight; the user goes on typing.
      await tester.enterText(brandField(), 'Acme');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      gate.complete();
      // Long enough for the answer to travel, short of the new debounce.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Before the new lookup's timer has fired: the old answer is not shown.
      expect(find.text('Bambu PLA Basic'), findsNothing);
      expect(
        find.text(pl.inventoryProfileDefaultPrefilled('PLA')),
        findsNothing,
      );
      await afterTyping(tester);

      // Acme PLA has no default.
      expect(find.text('Bambu PLA Basic'), findsNothing);
      expect(lookups(), ['PLA', 'PLA']);
    });

    testWidgets('a failed lookup takes out what the previous product\'s '
        'default put in', (tester) async {
      await openForm(
        tester,
        resolver: (_) => _basic(),
        failFor: (p) => p.brand == 'Boom',
      );
      await typeCombo(tester, materialField(), 'PLA');
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);

      await typeCombo(tester, brandField(), 'Boom');

      expect(find.text('Bambu PLA Basic @BBL X1C'), findsNothing);
      expect(find.text('Bambu PLA Basic'), findsNothing);
      expect(
        find.text(pl.inventoryProfileDefaultPrefilled('Boom PLA')),
        findsNothing,
      );
    });

    testWidgets('the note is shown only when the form was filled from the '
        'default', (tester) async {
      await openForm(
        tester,
        resolver: (_) => {
          'slicer_filament': 'GFA00',
          'slicer_filament_name': 'Bambu PLA Basic',
          'presets': [],
        },
        presets: const [
          SlicerPreset(
            source: 'cloud',
            id: 'MINE',
            name: 'My own PLA',
            filamentType: 'PLA',
          ),
        ],
      );
      await tester.tap(find.text(pl.inventorySlicerPresetNone));
      await settle(tester);
      await tester.tap(find.text('My own PLA'));
      await settle(tester);

      await typeCombo(tester, materialField(), 'PLA');

      // The default's preset lost to the user's pick and it has no model rows.
      expect(find.text('My own PLA'), findsOneWidget);
      expect(
        find.text(pl.inventoryProfileDefaultPrefilled('PLA')),
        findsNothing,
      );
    });

    testWidgets('typing in another field while a lookup is in flight does not '
        'ask again and drop its answer', (tester) async {
      final gate = Completer<void>();
      await openForm(
        tester,
        resolver: (_) => _basic(),
        gate: gate,
        holdWhen: (_) => true,
      );
      await typeCombo(tester, materialField(), 'PLA');
      // The same product spelled another way: the key is trimmed and folded.
      await tester.enterText(materialField(), 'pla ');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));

      gate.complete();
      await afterTyping(tester);

      expect(lookups(), ['PLA']);
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);
    });

    testWidgets('the note goes when the user replaces what it was about', (
      tester,
    ) async {
      await openForm(
        tester,
        resolver: (_) => {
          'slicer_filament': 'GFA00',
          'slicer_filament_name': 'Bambu PLA Basic',
          'presets': [],
        },
        presets: const [
          SlicerPreset(
            source: 'cloud',
            id: 'MINE',
            name: 'My own PLA',
            filamentType: 'PLA',
          ),
        ],
      );
      await typeCombo(tester, materialField(), 'PLA');
      expect(
        find.text(pl.inventoryProfileDefaultPrefilled('PLA')),
        findsOneWidget,
      );

      await tester.tap(find.text('Bambu PLA Basic'));
      await settle(tester);
      await tester.tap(find.text('My own PLA'));
      await settle(tester);

      expect(find.text('My own PLA'), findsOneWidget);
      expect(
        find.text(pl.inventoryProfileDefaultPrefilled('PLA')),
        findsNothing,
      );
    });

    testWidgets('a model the user cleared is not filled again', (tester) async {
      await openForm(tester, resolver: (_) => _basic());
      await typeCombo(tester, materialField(), 'PLA');
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsOneWidget);

      await tester.tap(find.byTooltip(pl.clear).last);
      await settle(tester);
      expect(find.text('Bambu PLA Basic @BBL X1C'), findsNothing);

      await typeCombo(tester, brandField(), 'Bambu Lab');

      expect(find.text('Bambu PLA Basic @BBL X1C'), findsNothing);
    });

    testWidgets('a server without profile defaults is never asked and offers '
        'no switch', (tester) async {
      await openForm(tester, supported: false, resolver: (_) => _basic());

      await typeCombo(tester, materialField(), 'PLA');

      expect(server.requests, isEmpty);
      expect(defaultSwitch(), findsNothing);
    });

    testWidgets('a lookup that fails leaves the form alone', (tester) async {
      await openForm(tester, resolveStatus: 500);

      await typeCombo(tester, materialField(), 'PLA');

      expect(find.text('Bambu PLA Basic'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('use as default', () {
    testWidgets('the switch waits for a material', (tester) async {
      await openForm(tester);

      expect(
        find.text(pl.inventoryProfileDefaultNeedsMaterial),
        findsOneWidget,
      );
      expect(tester.widget<SwitchListTile>(defaultSwitch()).onChanged, isNull);

      await typeCombo(tester, materialField(), 'PLA');

      expect(find.text(pl.inventoryProfileDefaultFor('PLA')), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(defaultSwitch()).onChanged,
        isNotNull,
      );
    });

    testWidgets('off by default: saving the spool writes no default and '
        'reads no list', (tester) async {
      await openForm(tester, resolver: (_) => _basic());
      await typeCombo(tester, materialField(), 'PLA');

      await tester.tap(saveButton());
      await settle(tester);

      expect(inventory.writes, ['create']);
      expect(calls().where((c) => !c.contains('resolve')), isEmpty);
    });

    testWidgets('on: saves what the form shows and sends back the K profiles '
        'the server holds', (tester) async {
      final k = {
        'printer_id': 1,
        'extruder': 0,
        'nozzle_diameter': '0.4',
        'k_value': 0.02,
        'name': 'Bambu PLA Basic',
      };
      await openForm(
        tester,
        resolver: (_) => _basic(),
        stored: [
          _stored(4, k: [k]),
        ],
      );
      await typeCombo(tester, materialField(), 'PLA');
      await tester.tap(defaultSwitch());
      await settle(tester);
      expect(find.text(pl.inventoryProfileDefaultAllColors), findsOneWidget);

      await tester.tap(saveButton());
      await settle(tester);

      expect(inventory.writes, ['create']);
      final body = writesOf(server.requests).single.body! as Map;
      expect(body['k_profiles'], [k]);
      expect(body['color_name'], '');
      expect(body['slicer_filament'], 'GFA00');
      expectSentAsRecorded(
        'inventory_profile_default_save',
        writesOf(server.requests),
      );
    });

    testWidgets('only this colour saves the colour\'s own row and keeps '
        'that row\'s K profiles, not the all-colours ones', (tester) async {
      final all = {'printer_id': 1, 'k_value': 0.02};
      final red = {'printer_id': 1, 'k_value': 0.05};
      await openForm(
        tester,
        resolver: (_) => _basic(),
        stored: [
          _stored(4, k: [all]),
          _stored(5, color: 'Red', k: [red]),
        ],
      );
      await typeCombo(tester, materialField(), 'PLA');
      await typeField(tester, colorField(), 'Red');
      await tester.tap(defaultSwitch());
      await settle(tester);
      await tester.tap(find.byType(DropdownMenu<bool>));
      await settle(tester);
      await tester.tap(
        find.text(pl.inventoryProfileDefaultColorOnly('Red')).last,
      );
      await settle(tester);

      await tester.tap(saveButton());
      await settle(tester);

      final body = writesOf(server.requests).single.body! as Map;
      expect(body['color_name'], 'Red');
      expect(body['k_profiles'], [red]);
    });

    testWidgets('only this colour needs a colour: with none typed the scope '
        'is every colour', (tester) async {
      await openForm(tester, resolver: (_) => _basic());
      await typeCombo(tester, materialField(), 'PLA');
      await tester.tap(defaultSwitch());
      await settle(tester);

      await tester.tap(find.byType(DropdownMenu<bool>));
      await settle(tester);

      expect(
        find.text(pl.inventoryProfileDefaultColorOnly('Red')),
        findsNothing,
      );
    });

    testWidgets('a colour picked and then cleared saves for every colour', (
      tester,
    ) async {
      await openForm(tester, resolver: (_) => _basic());
      await typeCombo(tester, materialField(), 'PLA');
      await typeField(tester, colorField(), 'Red');
      await tester.tap(defaultSwitch());
      await settle(tester);
      await tester.tap(find.byType(DropdownMenu<bool>));
      await settle(tester);
      await tester.tap(
        find.text(pl.inventoryProfileDefaultColorOnly('Red')).last,
      );
      await settle(tester);
      await typeField(tester, colorField(), '');

      await tester.tap(saveButton());
      await settle(tester);

      final body = writesOf(server.requests).single.body! as Map;
      expect(body['color_name'], '');
    });

    testWidgets('a refused default still closes the sheet, warns, and made '
        'the spool once', (tester) async {
      await openForm(tester, resolver: (_) => _basic(), putStatus: 403);
      await typeCombo(tester, materialField(), 'PLA');
      await tester.tap(defaultSwitch());
      await settle(tester);

      await tester.tap(saveButton());
      await settle(tester);

      expect(inventory.writes, ['create']);
      expect(find.text(pl.inventoryNewSpool), findsNothing);
      expect(find.text(pl.inventoryProfileDefaultSaveFailed), findsOneWidget);
      expect(find.text(pl.inventorySpoolCreated), findsNothing);
    });
  });

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('the default row fits at text scale $scale', (tester) async {
      await openForm(tester, resolver: (_) => _basic(), textScale: scale);
      await typeCombo(tester, materialField(), 'PLA');
      await typeField(tester, colorField(), 'Red');
      await tester.tap(defaultSwitch());
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(defaultSwitch()).height, greaterThanOrEqualTo(48));
      expect(find.byType(DropdownMenu<bool>), findsOneWidget);
      final width = tester.getSize(find.byType(DropdownMenu<bool>)).width;
      expect(width, greaterThan(200));
    });
  }
}
