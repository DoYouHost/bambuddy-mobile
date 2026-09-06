import 'package:flutter/material.dart';

import '../wear_theme.dart';

/// The line at the top of a watch screen.
///
/// Written out four times before this — the control screen, the picker,
/// settings and setup — and only the one carrying a printer name remembered to
/// ellipsize, because only that one had a string long enough to notice. A
/// localized title is just as able to run past the chord the circle leaves: the
/// ellipsis belongs to the role, not to the one call site that got bitten.
class WearHeader extends StatelessWidget {
  const WearHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: WearText.title,
    ),
  );
}
