import 'package:bambuddy_mobile/core/models/inventory_reference.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// What a fresh bambuddy server seeds into its colour catalogue: the 638 rows
/// of `DEFAULT_COLOR_CATALOG` (`backend/app/core/catalog_defaults.py`, server
/// f52dbb8), in the order `GET /inventory/colors` returns them.
final realCatalogue = [
  for (final json in readFixture('color_catalog_default.json') as List)
    ColorEntry.fromJson(json as Map<String, dynamic>),
];

/// Colours a user adds (`POST /inventory/colors`) in the shapes the seed never
/// has, written as the server stores them (`routes/inventory.py::ColorEntryCreate`,
/// `schemas/spool.py::normalize_extra_colors`, `normalize_effect_type`). Built
/// from the schema, not read off a server.
const customColours = [
  ColorEntry(
    id: 1001,
    manufacturer: 'Workshop',
    colorName: 'Galaxy Night',
    hexColor: '#1A1A2E',
    material: 'PLA',
    extraColors: '1a1a2e,4b0082,ffd700',
    effectType: 'galaxy',
  ),
  ColorEntry(
    id: 1002,
    manufacturer: 'Workshop',
    colorName: 'Smoke Tint',
    hexColor: '#40404080',
    material: 'PETG',
    effectType: 'translucent',
  ),
  ColorEntry(
    id: 1003,
    manufacturer: '',
    colorName: 'Unlabelled Teal',
    hexColor: '#008080',
  ),
];

/// [realCatalogue] with [customColours] where `GET /inventory/colors` sorts
/// them: by manufacturer, material, name.
final catalogueWithCustom = [...realCatalogue, ...customColours]
  ..sort(
    (a, b) => [
      a.manufacturer.compareTo(b.manufacturer),
      (a.material ?? '').compareTo(b.material ?? ''),
      a.colorName.compareTo(b.colorName),
    ].firstWhere((c) => c != 0, orElse: () => 0),
  );

/// The height of the on-screen keyboard [showKeyboard] opens, in dp: a phone
/// keyboard with its suggestion strip.
const keyboardHeight = 320.0;

void showKeyboard(WidgetTester tester) {
  tester.view.viewInsets = FakeViewPadding(
    bottom: keyboardHeight * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.resetViewInsets);
}

/// The y where an open keyboard starts, in logical pixels.
double keyboardTop(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio -
    keyboardHeight;

/// The catalogue sheet's list; the search field has a horizontal scrollable
/// of its own.
Finder catalogueList() => find
    .descendant(
      of: find.byType(ColorCatalogueSheet),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;

/// Drags the sheet's list with a finger until it goes no further: the sheet
/// first rises to full height, then the list scrolls.
Future<void> dragCatalogueToEnd(WidgetTester tester) async {
  for (var i = 0; i < 300; i++) {
    final position = tester.state<ScrollableState>(catalogueList()).position;
    if (position.pixels >= position.maxScrollExtent) return;
    await tester.drag(catalogueList(), const Offset(0, -600));
    await tester.pumpAndSettle();
  }
  fail('the catalogue never reached its end');
}

/// The option lowest on screen; after [dragCatalogueToEnd], the list's last.
Finder lowestOption(WidgetTester tester, Finder options) {
  final count = options.evaluate().length;
  expect(count, greaterThan(0), reason: 'no option is on screen');
  var lowest = 0;
  for (var i = 1; i < count; i++) {
    if (tester.getRect(options.at(i)).bottom >
        tester.getRect(options.at(lowest)).bottom) {
      lowest = i;
    }
  }
  return options.at(lowest);
}

/// The name an option tile shows.
String optionName(WidgetTester tester, Finder option) => tester
    .widget<Text>(find.descendant(of: option, matching: find.byType(Text)))
    .data!;

/// The colours the sheet lists for [shown] and [query], top to bottom.
List<ColorEntry> listedEntries(List<ColorEntry> shown, [String query = '']) => [
  for (final row in catalogueRows(shown, query)) ?row.entry,
];

/// The name the sheet lists last for [shown] and [query].
String lastListed(List<ColorEntry> shown, [String query = '']) =>
    listedEntries(shown, query).last.colorName;
