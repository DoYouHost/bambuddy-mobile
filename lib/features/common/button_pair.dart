import 'package:flutter/material.dart';

import '../../core/format/text_measure.dart';

/// Two buttons side by side — but only while both labels fit on one line.
///
/// A wrapped label grows just its own button, leaving the pair mismatched and
/// ragged, so below that width they stack full-width instead (which also
/// unwraps the labels). A `Wrap` gets this wrong in a subtler way: it keeps
/// each button at its own content width, so the stacked result is two buttons
/// of different lengths hanging off the left margin.
///
/// Whether a label fits depends on the locale, the user's text scale and the
/// padding this app's theme sets on buttons, so the width each one needs is
/// **measured from the resolved [ButtonStyle] the button will render with** —
/// never from `labelLarge` or a breakpoint. The theme sets horizontal padding
/// 20 and Manrope w700 while `labelLarge` is w500, which is how constants
/// underestimated a label by ~11 px: invisible at the default text size and
/// wrong at "small" on a 360 dp screen.
class ButtonPair extends StatelessWidget {
  const ButtonPair({
    super.key,
    required this.primary,
    required this.secondary,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.primaryStyle,
    this.secondaryStyle,
    this.hasIcons = true,
  });

  /// The buttons as they will be rendered, already tagged for the log.
  final Widget primary;
  final Widget secondary;

  /// The text each one paints, for the measurement. Passed rather than read off
  /// the widget: the label may be wrapped in anything.
  final String primaryLabel;
  final String secondaryLabel;

  /// The style each button resolves with. Null falls back to the ambient
  /// [FilledButtonTheme] / [OutlinedButtonTheme] — right for a button that took
  /// no `style:` of its own, wrong for one that did, which is why it is a
  /// parameter at all.
  final ButtonStyle? primaryStyle;
  final ButtonStyle? secondaryStyle;

  /// Whether these are `*.icon` buttons, whose icon box and gap are the only
  /// parts of the width not exposed through [ButtonStyle].
  final bool hasIcons;

  static const double _iconWidth = 18;
  static const double _iconGap = 8;

  /// A label has to fit with room to spare, not by a hair — measurement and
  /// rendering can round apart. Borderline pairs stack, which still looks
  /// right; a wrapped one does not.
  static const double _slack = 10;

  static const double _gap = 12;

  double _singleLineWidth(
    BuildContext context,
    String label,
    ButtonStyle? style,
  ) {
    const states = <WidgetState>{};
    final textStyle =
        (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).merge(
          style?.textStyle?.resolve(states),
        );
    final padding = style?.padding?.resolve(states)?.horizontal ?? 0;
    final icon = hasIcons ? _iconWidth + _iconGap : 0;
    return padding + icon + textWidth(context, label, textStyle);
  }

  @override
  Widget build(BuildContext context) {
    final needed = [
      _singleLineWidth(
        context,
        primaryLabel,
        primaryStyle ?? FilledButtonTheme.of(context).style,
      ),
      _singleLineWidth(
        context,
        secondaryLabel,
        secondaryStyle ?? OutlinedButtonTheme.of(context).style,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - _gap) / 2;
        if (needed.every((w) => w + _slack <= half)) {
          return Row(
            children: [
              Expanded(child: primary),
              const SizedBox(width: _gap),
              Expanded(child: secondary),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(width: double.infinity, child: primary),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: secondary),
          ],
        );
      },
    );
  }
}
