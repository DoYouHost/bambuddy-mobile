import 'dart:async';

import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/core/models/swatch_code.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/swatches/swatch_providers.dart';
import 'package:bambuddy_mobile/features/swatches/swatches_screen.dart';
import 'package:dash_kit/dash_kit.dart' show DashLoading;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';
import '../common/colour_catalogue_kit.dart';

/// The swatch form picks from the same catalogue sheet as the spool form
/// (#63): narrowed to its brand, material and variant, every colour named.
class _Codes extends SwatchCodesNotifier {
  _Codes(this.code);

  final SwatchCode code;

  @override
  List<SwatchCode> build() => [code];
}

const _matteIvory = SwatchCode(
  code: 'K7M2XQ',
  material: 'PLA',
  brand: 'Bambu Lab',
  variant: 'Matte',
  colorName: 'Ivory White',
  rgba: 'FFFFFFFF',
);

/// No catalogue entry has this brand or material, so the sheet lists all.
const _unknownIvory = SwatchCode(
  code: 'Q2W3E4',
  material: 'XYZ',
  brand: 'Nobody',
  colorName: 'Ivory White',
  rgba: 'FFFFFFFF',
);

ColorEntry _entry(String name, String hex, String material) => ColorEntry(
  id: '$name$material'.hashCode,
  manufacturer: 'Bambu Lab',
  colorName: name,
  hexColor: hex,
  material: material,
);

final _catalogue = [
  _entry('Jade White', '#FFFFFF', 'PLA Basic'),
  _entry('Bone White', '#CBC6B8', 'PLA Matte'),
  _entry('Ivory White', '#FFFFFF', 'PLA Matte'),
];

final _options = find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.identifier?.startsWith('swatch_form.color_option') ??
          false),
);

Finder _option(String name) =>
    find.descendant(of: _options, matching: find.text(name));

Future<void> _openCatalogue(
  WidgetTester tester, {
  SwatchCode code = _matteIvory,
  List<ColorEntry>? catalogue,
  Future<List<ColorEntry>>? loading,
  double scale = 1,
}) async {
  useLogicalWindow(tester, const Size(360, 800));
  await pumpPhone(
    tester,
    const SwatchesScreen(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    overrides: [
      noServerProfileOverride,
      swatchCodesProvider.overrideWith(() => _Codes(code)),
      uncodedFilamentsProvider.overrideWithValue(const []),
      colorCatalogProvider.overrideWith(
        (ref) => loading ?? Future.value(catalogue ?? _catalogue),
      ),
    ],
  );
  await settle(tester);
  await tester.tap(byLogId('swatches.card').first);
  await settle(tester);
  await tester.tap(byLogId('swatch_form.pick_color'));
  await settle(tester);
}

String _field(WidgetTester tester, String id) => tester
    .widget<EditableText>(
      find.descendant(of: byLogId(id), matching: find.byType(EditableText)),
    )
    .controller
    .text;

void main() {
  testWidgets('the sheet takes the swatch\'s brand, material and variant', (
    tester,
  ) async {
    await _openCatalogue(tester);

    expect(_options, findsNWidgets(2));
    expect(_option('Jade White'), findsNothing);
    final ivory = find.ancestor(
      of: _option('Ivory White'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: ivory, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('a picked colour fills the name and the hex', (tester) async {
    await _openCatalogue(tester);
    await tester.tap(_option('Bone White'));
    await settle(tester);

    expect(_options, findsNothing);
    expect(_field(tester, 'swatch_form.color_name'), 'Bone White');
    expect(_field(tester, 'swatch_form.rgba'), 'CBC6B8');
  });

  testWidgets('a catalogue still loading shows progress, not "none"', (
    tester,
  ) async {
    await _openCatalogue(tester, loading: Completer<List<ColorEntry>>().future);
    expect(find.byType(DashLoading), findsOneWidget);
    expect(find.text(pl.swatchNoCatalogColors), findsNothing);
  });

  testWidgets('an empty catalogue says to type the colour in', (tester) async {
    await _openCatalogue(tester, catalogue: const []);
    expect(find.text(pl.swatchNoCatalogColors), findsOneWidget);
    expect(_options, findsNothing);
  });

  group('with the catalogue a server seeds', () {
    testWidgets('the last of its 638 colours is reachable and fills the form', (
      tester,
    ) async {
      await _openCatalogue(
        tester,
        code: _unknownIvory,
        catalogue: realCatalogue,
      );
      await dragCatalogueToEnd(tester);

      final last = lowestOption(tester, _options);
      final name = optionName(tester, last);
      expect(name, lastListed(realCatalogue));
      await tester.tap(last);
      await settle(tester);

      expect(_field(tester, 'swatch_form.color_name'), name);
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets(
        'with the keyboard open the search and the last result stay above it '
        'at ${scale * 100}% text',
        (tester) async {
          await _openCatalogue(
            tester,
            code: _unknownIvory,
            catalogue: realCatalogue,
            scale: scale,
          );
          await tester.enterText(byLogId('swatch_form.color_search'), 'white');
          showKeyboard(tester);
          await settle(tester);

          expect(
            tester.getRect(byLogId('swatch_form.color_search')).bottom,
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
          expect(_field(tester, 'swatch_form.color_name'), name);
        },
      );
    }

    testWidgets('dragging the sheet down closes it and keeps the colour', (
      tester,
    ) async {
      await _openCatalogue(tester, catalogue: realCatalogue);
      await tester.fling(
        find.text(pl.inventoryColorPickTitle).last,
        const Offset(0, 500),
        1500,
      );
      await settle(tester);

      expect(_options, findsNothing);
      expect(_field(tester, 'swatch_form.color_name'), 'Ivory White');
      expect(_field(tester, 'swatch_form.rgba'), 'FFFFFFFF');
    });

    testWidgets('a multi-colour custom colour fills its name and main hex', (
      tester,
    ) async {
      await _openCatalogue(
        tester,
        code: const SwatchCode(
          code: 'W0RK51',
          material: 'PLA',
          brand: 'Workshop',
        ),
        catalogue: catalogueWithCustom,
      );
      expect(_options, findsOneWidget, reason: 'the maker has one PLA');
      await tester.tap(_option('Galaxy Night'));
      await settle(tester);

      expect(_field(tester, 'swatch_form.color_name'), 'Galaxy Night');
      expect(_field(tester, 'swatch_form.rgba'), '1A1A2E');
    });

    testWidgets(
      'a colour with neither maker nor material is found and picked',
      (tester) async {
        await _openCatalogue(
          tester,
          code: _unknownIvory,
          catalogue: catalogueWithCustom,
        );
        await tester.enterText(
          byLogId('swatch_form.color_search'),
          'unlabelled',
        );
        await settle(tester);
        expect(_options, findsOneWidget);
        await tester.tap(_option('Unlabelled Teal'));
        await settle(tester);

        expect(_field(tester, 'swatch_form.color_name'), 'Unlabelled Teal');
        expect(_field(tester, 'swatch_form.rgba'), '008080');
      },
    );

    testWidgets('a double tap on a colour picks it and leaves the form open', (
      tester,
    ) async {
      await _openCatalogue(tester, catalogue: realCatalogue);
      await tester.tap(_option('Bone White'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(_option('Bone White'), warnIfMissed: false);
      await settle(tester);

      expect(_options, findsNothing);
      expect(byLogId('swatch_form.save'), findsOneWidget);
      expect(_field(tester, 'swatch_form.color_name'), 'Bone White');
    });
  });
}
