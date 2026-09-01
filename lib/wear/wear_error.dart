import 'package:flutter/material.dart';

import 'wear_theme.dart';

/// How a failure looks on a watch: one short line, in the error colour, under
/// whatever caused it.
///
/// The two screens that show one had grown their own copy of this — the setup
/// flow trimmed at 80 characters with its own style helper, the control screen
/// at 60 with none — and neither number was anyone's decision. They are both
/// kept, as named constants with the reason attached: what a message may spend
/// is decided by the room it is given, not by how long it is up for. That is
/// why the passing message is now the longer of the two — it owns the whole
/// face, while the one that stays sits under a button on a screen that still
/// has to fit everything else.

/// A message that stays on screen until something replaces it, so it may run to
/// a second line without costing anyone the thing they were reading.
const wearErrorMaxChars = 80;

/// A message in a `WearToast`, gone in three seconds.
///
/// It was 60 while this was a snackbar, which was one line of a bar most of
/// which sat off the glass anyway. The message now gets the middle of the face
/// and four lines of it: the inscribed rectangle on the smallest supported face
/// is around 142 dp wide and `WearText.body` averages some 6 dp a character, so
/// four lines hold roughly 90. What actually enforces the shape is the widget's
/// `maxLines` ellipsis; this cap is only here so that a 300-character exception
/// string cannot arrive as a wall of grey.
const wearToastMaxChars = 100;

/// The line itself: small, in the theme's error colour.
TextStyle wearErrorStyle(BuildContext context) =>
    WearText.small.copyWith(color: Theme.of(context).colorScheme.error);

/// [text] trimmed to [max] characters, with an ellipsis where it was cut.
///
/// Only ever shortens: a message already inside the budget comes back exactly
/// as it was, ellipsis included or not.
String wearShortText(String text, {required int max}) =>
    text.length > max ? '${text.substring(0, max)}…' : text;
