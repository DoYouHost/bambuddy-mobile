import 'package:bambuddy_mobile/core/models/swatch_code.dart';
import 'package:bambuddy_mobile/features/swatches/swatch_providers.dart';
import 'package:bambuddy_mobile/features/swatches/swatches_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets of the swatch codes screen: the empty
/// registry over the demo shelf, a filled one, the search miss, the create and
/// edit sheets with their validation errors, the colour catalogue behind them
/// and the delete confirmation. Deliberately not covered: the import
/// confirmation, which sits behind the platform file picker a widget test cannot
/// answer, and the snackbars (copy, export), which are transient.
void main() {
  a11ySurface(
    'swatches, no codes yet',
    home: () => const SwatchesScreen(),
    shows: find.text(pl.swatchNoCodes),
  );

  a11ySurface(
    'swatches, codes and uncoded filaments',
    overrides: [_codesOverride],
    home: () => const SwatchesScreen(),
    shows: find.text(pl.swatchSectionUncoded.toUpperCase()),
  );

  a11ySurface(
    'swatches, every filament coded',
    overrides: [_codesOverride, uncodedFilamentsProvider.overrideWithValue([])],
    home: () => const SwatchesScreen(),
    shows: find.text(pl.swatchAllCoded),
  );

  a11ySurface(
    'swatches, search without a match',
    overrides: [_codesOverride],
    home: () => const SwatchesScreen(),
    arrange: (tester) async {
      await tester.enterText(byLogId('swatches.search'), 'zzzzzz');
    },
    shows: find.text(pl.swatchNoMatch('zzzzzz')),
  );

  a11ySurface(
    'swatches, create sheet',
    overrides: [_codesOverride],
    home: () => const SwatchesScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('swatches.create'));
    },
    shows: find.text(pl.swatchFormTitle),
  );

  a11ySurface(
    'swatches, create sheet with its errors',
    overrides: [_codesOverride],
    home: () => const SwatchesScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('swatches.create'));
      await settle(tester);
      await tester.tap(byLogId('swatch_form.save'));
    },
    shows: find.text(pl.swatchMaterialRequired),
  );

  a11ySurface(
    'swatches, edit sheet',
    overrides: [_codesOverride],
    home: () => const SwatchesScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('swatches.card').first);
    },
    shows: find.text(pl.swatchEditTitle),
  );

  a11ySurface(
    'swatches, colour catalogue',
    overrides: [_codesOverride],
    home: () => const SwatchesScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('swatches.create'));
      await settle(tester);
      await tester.tap(byLogId('swatch_form.pick_color'));
    },
    shows: find.text(pl.inventoryColorPickTitle),
  );

  a11ySurface(
    'swatches, delete confirmation',
    overrides: [_codesOverride],
    home: () => const SwatchesScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('swatches.delete').first);
    },
    shows: find.text(pl.swatchDeleteTitle),
  );
}

/// Two coded filaments; the rest of the demo shelf stays uncoded. Only `build`
/// is replaced, so saving and deleting still go through the real storage.
final _codesOverride = swatchCodesProvider.overrideWith(_Codes.new);

class _Codes extends SwatchCodesNotifier {
  @override
  List<SwatchCode> build() => const [
    SwatchCode(
      code: 'K7M2XQ',
      material: 'PLA',
      brand: 'Bambu Lab',
      variant: 'Basic',
      colorName: 'Black',
      rgba: '000000FF',
    ),
    SwatchCode(
      code: 'H4R9TC',
      material: 'PETG',
      brand: 'Bambu Lab',
      variant: 'HF',
      colorName: 'White',
      rgba: 'FFFFFFFF',
    ),
  ];
}
