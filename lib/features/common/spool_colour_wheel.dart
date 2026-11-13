import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';

/// The side margin of the dialogs that hold a [SpoolColourWheel]. The package
/// sizes the hex field at ten and a half times its font size, 294 dp at 200 %
/// text, which the default 40 dp margins (280 dp on a 360 dp phone) cut.
const spoolColourDialogInset = EdgeInsets.symmetric(
  horizontal: DashSpace.lg,
  vertical: DashSpace.xl,
);

/// The HSV wheel and editable hex code both spool colour dialogs show: the
/// AMS slot's and the inventory's.
class SpoolColourWheel extends StatelessWidget {
  const SpoolColourWheel({
    super.key,
    required this.color,
    required this.onChanged,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final base =
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: DashFontSize.title);
    // The package sizes the code field from the style's font size and ignores
    // the text scale, so a scaled code overflowed and scrolled out of sight.
    // The scale goes into the font size instead, applied once.
    final code = base.copyWith(
      fontSize: MediaQuery.textScalerOf(
        context,
      ).scale(base.fontSize ?? DashFontSize.title),
    );
    return MediaQuery.withNoTextScaling(
      child: ColorPicker(
        color: color,
        onColorChanged: onChanged,
        pickersEnabled: const {
          ColorPickerType.primary: false,
          ColorPickerType.accent: false,
          ColorPickerType.wheel: true,
        },
        enableShadesSelection: false,
        // The printer has no use for a transparent filament: a zero alpha is
        // how it reports an *empty* slot, so the picker never offers it.
        enableOpacity: false,
        showColorCode: true,
        colorCodeTextStyle: code,
        // `#RRGGBB`, as every hex in the app reads. The field's width is fixed
        // by the package, and its `0xAA` prefix and copy button left the six
        // digits too little of it ("0ACC38" was cut at 100 %); copying stays
        // in the long-press menu.
        copyPasteBehavior: const ColorPickerCopyPasteBehavior(
          copyFormat: ColorPickerCopyFormat.numHexRRGGBB,
          editFieldCopyButton: false,
        ),
      ),
    );
  }
}
