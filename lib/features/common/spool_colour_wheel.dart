import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

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
  Widget build(BuildContext context) => ColorPicker(
    color: color,
    onColorChanged: onChanged,
    pickersEnabled: const {
      ColorPickerType.primary: false,
      ColorPickerType.accent: false,
      ColorPickerType.wheel: true,
    },
    enableShadesSelection: false,
    // The printer has no use for a transparent filament: a zero alpha is how
    // it reports an *empty* slot, so the picker never offers it.
    enableOpacity: false,
    showColorCode: true,
  );
}
