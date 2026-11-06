import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

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
      colorCatalogProvider.overrideWith((ref) async => catalogue ?? _catalogue),
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

    test('an empty catalogue has no rows', () {
      expect(catalogueRows(const [], ''), isEmpty);
    });
  });

  group('in the spool form', () {
    testWidgets('without a catalogue the field is not offered', (tester) async {
      await _openForm(tester, _matteIvory, catalogue: const []);
      expect(byLogId('spool_form.color_catalog'), findsNothing);
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

    testWidgets(
      'nothing matching lists the whole catalogue, one white ticked',
      (tester) async {
        await _openForm(tester, _unknownIvory);
        await _openCatalogue(tester);

        expect(find.text('Bambu Lab · PLA Basic'), findsOneWidget);
        expect(find.text('Bambu Lab · PLA Silk+'), findsOneWidget);
        // Three entries are #FFFFFF; only the one the spool is named after is
        // the spool's colour.
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
      },
    );

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
}
