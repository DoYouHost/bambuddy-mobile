import 'dart:async';

import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';
import '../common/colour_catalogue_kit.dart';

/// The spool form's colour catalogue (#63): a sheet narrowed to the form's
/// brand, material and variant, every colour named, the whites of one maker
/// apart under their material.
class _Shelf extends FixedInventory {
  _Shelf() : super(InventoryState());

  final drafts = <SpoolDraft>[];

  @override
  Future<void> refresh({bool askBackend = false}) async {}

  @override
  Future<Spool?> updateSpool(int spoolId, SpoolDraft draft) async {
    drafts.add(draft);
    return Spool(id: spoolId, material: draft.material);
  }
}

ColorEntry _entry(String maker, String name, String hex, String? material) =>
    ColorEntry(
      id: '$maker$name$material'.hashCode,
      manufacturer: maker,
      colorName: name,
      hexColor: hex,
      material: material,
    );

/// In the server's order (manufacturer, material, name). The last name is the
/// widest row the 200 % check needs.
final _catalogue = [
  _entry('Bambu Lab', 'Black', '#000000', 'PLA'),
  _entry('Bambu Lab', 'Jade White', '#FFFFFF', 'PLA Basic'),
  _entry('Bambu Lab', 'Bone White', '#CBC6B8', 'PLA Matte'),
  _entry('Bambu Lab', 'Ivory White', '#FFFFFF', 'PLA Matte'),
  _entry('Bambu Lab', 'White', '#FFFFFF', 'PLA Silk+'),
  _entry('eSUN', 'Warm White', '#F5F0E6', 'PLA+'),
  _entry('Protopasta', 'Cosmic Twilight Iridescent Purple', '#4B2A6B', null),
];

const _matteIvory = Spool(
  id: 1,
  material: 'PLA',
  brand: 'Bambu Lab',
  subtype: 'Matte',
  colorName: 'Ivory White',
  rgba: 'FFFFFFFF',
);

/// No catalogue entry has this brand or material, so the sheet lists all.
const _unknownIvory = Spool(
  id: 2,
  material: 'XYZ',
  brand: 'Nobody',
  colorName: 'Ivory White',
  rgba: 'FFFFFFFF',
);

/// A known material rides in the id (`spool_form.color_option@PLA`).
final _options = find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.identifier?.startsWith('spool_form.color_option') ?? false),
);

Finder _option(String name) =>
    find.descendant(of: _options, matching: find.text(name));

Future<_Shelf> _openForm(
  WidgetTester tester,
  Spool existing, {
  List<ColorEntry>? catalogue,
  Future<List<ColorEntry>>? loading,
  double scale = 1,
}) async {
  final shelf = _Shelf();
  useLogicalWindow(tester, const Size(360, 800));
  await pumpPhone(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => openSpoolForm(context, existing: existing),
          child: const Text('open'),
        ),
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    overrides: [
      inventoryProvider.overrideWith(() => shelf),
      noServerProfileOverride,
      inventoryRepositoryOf(InventoryBackend.native),
      inventoryBackendOverride(InventoryBackend.native),
      colorCatalogProvider.overrideWith(
        (ref) => loading ?? Future.value(catalogue ?? _catalogue),
      ),
      presetOverridesSupportedProvider.overrideWithValue(
        const AsyncData(false),
      ),
    ],
  );
  await tester.tap(find.text('open'));
  await settle(tester);
  return shelf;
}

Future<void> _openCatalogue(WidgetTester tester) async {
  await tester.ensureVisible(byLogId('spool_form.color_catalog'));
  await settle(tester);
  await tester.tap(byLogId('spool_form.color_catalog'));
  await settle(tester);
}

void main() {
  group('catalogueRows', () {
    test('a heading opens each maker-and-material run, in catalogue order', () {
      final rows = catalogueRows(_catalogue, '');
      expect(
        [for (final r in rows) r.heading ?? '  ${r.entry!.colorName}'],
        [
          'Bambu Lab · PLA',
          '  Black',
          'Bambu Lab · PLA Basic',
          '  Jade White',
          'Bambu Lab · PLA Matte',
          '  Bone White',
          '  Ivory White',
          'Bambu Lab · PLA Silk+',
          '  White',
          'eSUN · PLA+',
          '  Warm White',
          'Protopasta',
          '  Cosmic Twilight Iridescent Purple',
        ],
      );
    });

    test('the query matches name, maker and material, trimmed', () {
      List<String?> names(String q) =>
          catalogueRows(_catalogue, q).map((r) => r.entry?.colorName).toList();
      expect(names(' MATTE '), [null, 'Bone White', 'Ivory White']);
      expect(names('esun'), [null, 'Warm White']);
      expect(names('ivory'), [null, 'Ivory White']);
      expect(names('nothing like it'), isEmpty);
    });

    test('a run with neither maker nor material has no heading', () {
      final rows = catalogueRows([
        _entry('', 'Mystery', '#123456', null),
        ..._catalogue.take(1),
      ], '');
      expect(rows.first.entry?.colorName, 'Mystery');
      expect(rows.where((r) => r.heading == ''), isEmpty);
    });

    test('an empty catalogue has no rows', () {
      expect(catalogueRows(const [], ''), isEmpty);
    });
  });

  group('in the spool form', () {
    testWidgets('without a catalogue the field is not offered', (tester) async {
      await _openForm(tester, _matteIvory, catalogue: const []);
      expect(byLogId('spool_form.color_catalog'), findsNothing);
    });

    testWidgets('the field stays while the catalogue loads', (tester) async {
      await _openForm(
        tester,
        _matteIvory,
        loading: Completer<List<ColorEntry>>().future,
      );
      expect(byLogId('spool_form.color_catalog'), findsOneWidget);
    });

    testWidgets('brand, material and variant narrow the sheet to one line', (
      tester,
    ) async {
      await _openForm(tester, _matteIvory);
      await _openCatalogue(tester);

      expect(find.text('Bambu Lab · PLA Matte'), findsOneWidget);
      expect(_options, findsNWidgets(2));
      expect(_option('Ivory White'), findsOneWidget);
      expect(_option('Bone White'), findsOneWidget);
      expect(_option('Jade White'), findsNothing);
    });

    testWidgets('nothing matching lists the whole catalogue, nothing ticked', (
      tester,
    ) async {
      await _openForm(tester, _unknownIvory);
      await _openCatalogue(tester);

      expect(find.text('Bambu Lab · PLA Basic'), findsOneWidget);
      expect(find.text('Bambu Lab · PLA Silk+'), findsOneWidget);
      expect(_option('Ivory White'), findsOneWidget);
      // The form's brand and material matched none of it, so no entry is the
      // spool's colour, not even the one with its name and hex.
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('among the narrowed whites only the named one is ticked', (
      tester,
    ) async {
      await _openForm(
        tester,
        const Spool(
          id: 4,
          material: 'PLA',
          brand: 'Bambu Lab',
          colorName: 'Ivory White',
          rgba: 'FFFFFFFF',
        ),
      );
      await _openCatalogue(tester);

      // Jade White, Ivory White and White are all #FFFFFF here.
      expect(_option('Jade White'), findsOneWidget);
      expect(_option('White'), findsOneWidget);
      final ticks = find.descendant(
        of: _options,
        matching: find.byIcon(Icons.check),
      );
      expect(ticks, findsOneWidget);
      final ivory = find.ancestor(
        of: _option('Ivory White'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: ivory, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('a spool with no colour name ticks nothing', (tester) async {
      await _openForm(
        tester,
        const Spool(
          id: 5,
          material: 'PLA',
          brand: 'Bambu Lab',
          subtype: 'Matte',
          rgba: 'CBC6B8FF',
        ),
        catalogue: [
          ..._catalogue,
          _entry('Bambu Lab', '', '#CBC6B8', 'PLA Matte'),
        ],
      );
      await _openCatalogue(tester);

      expect(_options, findsNWidgets(3));
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('the tick ignores the case of the typed name', (tester) async {
      await _openForm(
        tester,
        const Spool(
          id: 3,
          material: 'PLA',
          brand: 'Bambu Lab',
          subtype: 'Matte',
          colorName: ' ivory WHITE ',
          rgba: 'FFFFFFFF',
        ),
      );
      await _openCatalogue(tester);
      final ivory = find.ancestor(
        of: _option('Ivory White'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: ivory, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('the search narrows further and says when nothing matches', (
      tester,
    ) async {
      await _openForm(tester, _unknownIvory);
      await _openCatalogue(tester);

      await tester.enterText(byLogId('spool_form.color_search'), 'silk');
      await settle(tester);
      expect(_options, findsOneWidget);
      expect(_option('White'), findsOneWidget);

      await tester.enterText(byLogId('spool_form.color_search'), 'zzz');
      await settle(tester);
      expect(_options, findsNothing);
      expect(find.text(pl.noSearchResults('zzz')), findsOneWidget);
    });

    testWidgets('a picked colour fills name and hex, and is what is saved', (
      tester,
    ) async {
      final shelf = await _openForm(tester, _matteIvory);
      await _openCatalogue(tester);
      await tester.tap(_option('Bone White'));
      await settle(tester);

      expect(_options, findsNothing);
      expect(find.text('#CBC6B8'), findsOneWidget);

      await scrollSheetDown(tester);
      await tester.tap(byLogId('spool_form.save'));
      await settle(tester);
      expect(shelf.drafts.single.colorName, 'Bone White');
      expect(shelf.drafts.single.rgba, 'CBC6B8FF');
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets(
        'the colour dialog\'s hex code reads in full at ${scale * 100}%',
        (tester) async {
          // The widest code the package sizes its field for.
          await _openForm(
            tester,
            const Spool(id: 6, material: 'PLA', rgba: 'DDDDDDFF'),
            scale: scale,
          );
          // Below the fold of a lazy list at large text: not built until near.
          // The form's list is the outermost scrollable around its fields.
          await tester.scrollUntilVisible(
            byLogId('spool_form.color'),
            100,
            scrollable: find
                .ancestor(
                  of: byLogId('spool_form.material'),
                  matching: find.byType(Scrollable),
                )
                .last,
          );
          await settle(tester);
          await tester.tap(byLogId('spool_form.color'));
          await settle(tester);
          final code = tester
              .state<EditableTextState>(find.byType(EditableText).last)
              .renderEditable;
          expect(code.text?.toPlainText(), 'DDDDDD');
          expect(
            code.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(code.size.width + 0.5),
          );
        },
      );
    }

    testWidgets('dismissing the sheet leaves the colour as it was', (
      tester,
    ) async {
      final shelf = await _openForm(tester, _matteIvory);
      await _openCatalogue(tester);
      await tester.tapAt(const Offset(180, 20));
      await settle(tester);

      await scrollSheetDown(tester);
      await tester.tap(byLogId('spool_form.save'));
      await settle(tester);
      expect(shelf.drafts.single.colorName, 'Ivory White');
      expect(shelf.drafts.single.rgba, 'FFFFFFFF');
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets('field and sheet fit at ${scale * 100}% text', (
        tester,
      ) async {
        await _openForm(tester, _unknownIvory, scale: scale);
        await _openCatalogue(tester);
        expect(tester.takeException(), isNull);

        await tester.enterText(byLogId('spool_form.color_search'), 'cosmic');
        await settle(tester);
        expect(_option('Cosmic Twilight Iridescent Purple'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('with the catalogue a server seeds', () {
    Future<_Shelf> save(WidgetTester tester, _Shelf shelf) async {
      await scrollSheetDown(tester);
      await tester.tap(byLogId('spool_form.save'));
      await settle(tester);
      return shelf;
    }

    testWidgets('the last of its 638 colours is reachable and is saved', (
      tester,
    ) async {
      final shelf = await _openForm(
        tester,
        _unknownIvory,
        catalogue: realCatalogue,
      );
      await _openCatalogue(tester);
      await dragCatalogueToEnd(tester);

      final last = lowestOption(tester, _options);
      final name = optionName(tester, last);
      expect(name, lastListed(realCatalogue));
      await tester.tap(last);
      await settle(tester);

      await save(tester, shelf);
      expect(shelf.drafts.single.colorName, name);
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets(
        'with the keyboard open the search and the last result stay above it '
        'at ${scale * 100}% text',
        (tester) async {
          final shelf = await _openForm(
            tester,
            _unknownIvory,
            catalogue: realCatalogue,
            scale: scale,
          );
          await _openCatalogue(tester);
          await tester.enterText(byLogId('spool_form.color_search'), 'white');
          showKeyboard(tester);
          await settle(tester);

          expect(
            tester.getRect(byLogId('spool_form.color_search')).bottom,
            lessThanOrEqualTo(keyboardTop(tester)),
          );
          await dragCatalogueToEnd(tester);
          final last = lowestOption(tester, _options);
          expect(
            tester.getRect(last).bottom,
            lessThanOrEqualTo(keyboardTop(tester)),
            reason: 'the last result hides under the keyboard',
          );
          final name = optionName(tester, last);
          expect(name, lastListed(realCatalogue, 'white'));
          await tester.tap(last);
          await settle(tester);
          expect(tester.takeException(), isNull);

          tester.view.resetViewInsets();
          await save(tester, shelf);
          expect(shelf.drafts.single.colorName, name);
        },
      );
    }

    testWidgets('dragging the sheet down closes it and keeps the colour', (
      tester,
    ) async {
      final shelf = await _openForm(
        tester,
        _matteIvory,
        catalogue: realCatalogue,
      );
      await _openCatalogue(tester);
      await tester.fling(
        find.text(pl.inventoryColorPickTitle).last,
        const Offset(0, 500),
        1500,
      );
      await settle(tester);

      expect(find.byType(ColorCatalogueSheet), findsNothing);
      await save(tester, shelf);
      expect(shelf.drafts.single.colorName, 'Ivory White');
      expect(shelf.drafts.single.rgba, 'FFFFFFFF');
    });

    testWidgets('a multi-colour custom colour saves its stops and effect', (
      tester,
    ) async {
      final shelf = await _openForm(
        tester,
        const Spool(id: 7, material: 'PLA', brand: 'Workshop'),
        catalogue: catalogueWithCustom,
      );
      await _openCatalogue(tester);
      expect(_options, findsOneWidget, reason: 'the maker has one PLA');
      await tester.tap(_option('Galaxy Night'));
      await settle(tester);

      await save(tester, shelf);
      final draft = shelf.drafts.single;
      expect(draft.colorName, 'Galaxy Night');
      expect(draft.rgba, '1A1A2EFF');
      expect(draft.extraColors, '1a1a2e,4b0082,ffd700');
      expect(draft.effectType, 'galaxy');
    });

    testWidgets('a plain colour clears the stops and effect the spool had', (
      tester,
    ) async {
      final shelf = await _openForm(
        tester,
        const Spool(
          id: 8,
          material: 'PLA',
          brand: 'Bambu Lab',
          subtype: 'Matte',
          colorName: 'Galaxy Night',
          rgba: '1A1A2EFF',
          extraColors: '1a1a2e,4b0082,ffd700',
          effectType: 'galaxy',
        ),
        catalogue: catalogueWithCustom,
      );
      await _openCatalogue(tester);
      await tester.tap(_option('Bone White'));
      await settle(tester);

      await save(tester, shelf);
      final draft = shelf.drafts.single;
      expect(draft.colorName, 'Bone White');
      expect(draft.extraColors ?? '', isEmpty);
      expect(draft.effectType, isNull);
    });

    testWidgets('a colour with neither maker nor material is found and saved', (
      tester,
    ) async {
      final shelf = await _openForm(
        tester,
        _unknownIvory,
        catalogue: catalogueWithCustom,
      );
      await _openCatalogue(tester);
      await tester.enterText(byLogId('spool_form.color_search'), 'unlabelled');
      await settle(tester);
      expect(_options, findsOneWidget);
      await tester.tap(_option('Unlabelled Teal'));
      await settle(tester);

      await save(tester, shelf);
      expect(shelf.drafts.single.colorName, 'Unlabelled Teal');
      expect(shelf.drafts.single.rgba, '008080FF');
    });

    // The web cuts a catalogue hex to six digits here (ColorSection.tsx:156)
    // while its own `selectColor` keeps eight (#1545); the app keeps the alpha
    // a user typed into the catalogue.
    testWidgets('a colour with an alpha is saved with it', (tester) async {
      final shelf = await _openForm(
        tester,
        const Spool(id: 10, material: 'PETG', brand: 'Workshop'),
        catalogue: catalogueWithCustom,
      );
      await _openCatalogue(tester);
      await tester.tap(_option('Smoke Tint'));
      await settle(tester);

      await save(tester, shelf);
      expect(shelf.drafts.single.rgba, '40404080');
    });

    testWidgets('a spool whose colour has an alpha is ticked in the sheet', (
      tester,
    ) async {
      await _openForm(
        tester,
        const Spool(
          id: 9,
          material: 'PETG',
          brand: 'Workshop',
          colorName: 'Smoke Tint',
          rgba: '40404080',
        ),
        catalogue: catalogueWithCustom,
      );
      await _openCatalogue(tester);
      final smoke = find.ancestor(
        of: _option('Smoke Tint'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: smoke, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('a double tap on a colour picks it and leaves the form open', (
      tester,
    ) async {
      final shelf = await _openForm(
        tester,
        _matteIvory,
        catalogue: realCatalogue,
      );
      await _openCatalogue(tester);
      await tester.tap(_option('Bone White'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(_option('Bone White'), warnIfMissed: false);
      await settle(tester);

      expect(find.byType(ColorCatalogueSheet), findsNothing);
      await save(tester, shelf);
      expect(shelf.drafts.single.colorName, 'Bone White');
    });
  });
}
