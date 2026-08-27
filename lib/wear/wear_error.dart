import 'package:flutter/material.dart';

import 'wear_theme.dart';

/// How a failure looks on a watch: one short line, in the error colour, under
/// whatever caused it.
///
/// The two screens that show one had grown their own copy of this — the setup
/// flow trimmed at 80 characters with its own style helper, the control screen
/// at 60 with none — and neither number was anyone's decision. They are both
/// kept, as named constants with the reason attached: the length that belongs
/// to a line is decided by how long the line is on screen.

/// A message that stays on screen until something replaces it, so it may run to
/// a second line without costing anyone the thing they were reading.
const wearErrorMaxChars = 80;

/// A message in a snackbar, gone in two seconds. What cannot be read in that
/// time is not worth the width.
const wearToastMaxChars = 60;

/// The line itself: small, in the theme's error colour.
TextStyle wearErrorStyle(BuildContext context) =>
    WearText.small.copyWith(color: Theme.of(context).colorScheme.error);

/// [text] trimmed to [max] characters, with an ellipsis where it was cut.
///
/// Only ever shortens: a message already inside the budget comes back exactly
/// as it was, ellipsis included or not.
String wearShortText(String text, {required int max}) =>
    text.length > max ? '${text.substring(0, max)}…' : text;
