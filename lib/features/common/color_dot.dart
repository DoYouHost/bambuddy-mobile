import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';

/// A colour as a small round mark. The hairline keeps black and white
/// filament visible on either theme; [ring] swaps it for a heavier outline,
/// which marks the picked one in a row of them. A null [color] draws the
/// outline only.
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    this.size = DashSize.d12,
    this.ring,
  });

  final Color? color;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: ring ?? t.hairline,
          width: ring != null ? DashStroke.regular : DashStroke.hairline,
        ),
      ),
    );
  }
}
