import 'package:flutter/widgets.dart';

/// How wide [text] would be on one line in [style], in the reading direction and
/// at the system font size it will actually be painted with.
///
/// The two layouts that ask — a button deciding whether its label fits beside
/// another one, a metadata row deciding whether it fits on one line — each had a
/// copy of this, and what is worth sharing is the part neither may forget: the
/// ambient [TextScaler], because a label measured at 1.0 and painted at 1.3
/// decides wrongly at exactly the font size where the decision matters, and the
/// [Directionality] the paragraph is laid out in.
///
/// [style] stays the caller's business — resolved from a `ButtonStyle` in one
/// place and from the ambient `DefaultTextStyle` in the other. Only the caller
/// knows which one its widget will paint with, and that has to be the one
/// measured.
double textWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}
