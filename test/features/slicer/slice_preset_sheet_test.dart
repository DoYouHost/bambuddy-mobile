import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/features/slicer/slice_preset_sheet.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The filament sheet's filters: options from what the user owns, the plate's
/// material and the selected printer to start on, the whole catalogue behind
/// "All".
void main() {
  final l10n = lookupAppLocalizations(const Locale('pl'));
  const registry = {'Bambu Lab H2D': 'H2D', 'Bambu Lab X1 Carbon': 'X1C'};

  SlicerPreset std(String name, [String? type]) =>
      SlicerPreset(source: 'cloud', id: name, name: name, filamentType: type);

  final catalog = [
    std('Generic PLA @BBL H2D', 'PLA'),
    std('Bambu PLA Basic @BBL H2D', 'PLA'),
    std('Generic PETG @BBL H2D', 'PETG'),
    std('Bambu PETG HF @BBL H2D'),
    std('Bambu PETG HF @BBL X1C'),
    std('eSUN ABS+ @BBL H2D', 'ABS'),
  ];

  Future<void> open(WidgetTester tester, {String? needs = 'PETG'}) async {
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPresetSheet(
                context,
                title: 'Filament',
                filtered: catalog.take(5).toList(),
                all: catalog,
                filament: FilamentChoices(
                  spoolPrinters: null,
                  matchFor: (_) => null,
                  ownedModels: const {'H2D'},
                  ownedMaterials: const {'PLA', 'PETG'},
                  ownedBrands: const {'Bambu'},
                  registry: registry,
                  printerModel: 'H2D',
                  needsMaterial: needs,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  List<String> shown(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(
      find.descendant(
        of: byLogId('slice.preset_option'),
        matching: find.byType(ListTile),
      ),
    ))
      ((tile.title! as Text).data!),
  ];

  testWidgets('starts on the printer and the plate\'s material', (
    tester,
  ) async {
    await open(tester);
    expect(shown(tester), ['Generic PETG @BBL H2D', 'Bambu PETG HF @BBL H2D']);
    expect(find.text(l10n.sliceProfilesShown(2, 5)), findsOneWidget);
    expect(find.text(l10n.sliceNeedsMaterial('PETG')), findsOneWidget);
  });

  testWidgets('offers only what the user owns until "All"', (tester) async {
    await open(tester);
    expect(find.widgetWithText(ChoiceChip, 'ABS'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'eSUN'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'X1C'), findsNothing);

    await tester.tap(byLogId('slice.show_all_presets'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'ABS'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'eSUN'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'X1C'), findsOneWidget);
  });

  testWidgets('a brand narrows, and its chip again clears it', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bambu'));
    await tester.pumpAndSettle();
    expect(shown(tester), ['Bambu PETG HF @BBL H2D']);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bambu'));
    await tester.pumpAndSettle();
    expect(shown(tester), hasLength(2));
  });

  testWidgets('a material nobody owns does not filter', (tester) async {
    // The plate asks for ABS, which is not a chip while "All" is off.
    await open(tester, needs: 'ABS');
    expect(
      find.text(l10n.sliceProfilesShown(4, 5)),
      findsOneWidget,
      reason: 'every H2D preset listed',
    );
  });

  testWidgets('a printer or process gets the list alone', (tester) async {
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPresetSheet(
                context,
                title: 'Printer',
                filtered: catalog,
                all: catalog,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(byLogId('slice.filament_tab'), findsNothing);
  });
}
