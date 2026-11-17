import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';

/// The small heading over a group of controls or rows: bold, in capitals, with
/// the scale's wide tracking for capitals, and marked as a heading for a screen
/// reader so "jump to next heading" lands on it.
///
/// One look for the whole app. A screen that wants its section titles to read
/// differently changes this widget, not its own copy of the style. A card's
/// title is another role (`titleSm` and `titleMd`), and so is a tile's caption
/// (`BambuddyAccent.caption`, kept tight for the temperature grid).
///
/// Capitals are made here, so a caller passes the string as the translation has
/// it. A control beside the heading stays outside it, as `SectionHeading` asks:
/// merged into the heading it stops reading as a button.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.overflow});

  final String text;

  /// For a heading that shares a row with controls and has to give way.
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: t.bodyBold.copyWith(letterSpacing: DashTracking.caps),
        overflow: overflow,
      ),
    );
  }
}
