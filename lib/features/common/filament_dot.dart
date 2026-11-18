import 'package:app_util/app_util.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';

/// A filament colour as a small round mark beside a name or a count. The
/// outline keeps black and white filament visible on either theme.
///
/// One dot for the archive's rows and calendar and the nozzle sheet. It is not
/// [ColorDot]: that one's outline is the hairline, and it takes a ring and a null
/// colour for a picker (see `docs/unification-lessons.md`).
class FilamentDot extends StatelessWidget {
  const FilamentDot({super.key, required this.color});

  /// The colour as the server sends it, an RGBA hex string.
  FilamentDot.hex(String hex, {Key? key})
    : this(key: key, color: colorFromHex(hex));

  final Color? color;

  static const size = 10.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: t.textTertiary),
      ),
    );
  }
}
