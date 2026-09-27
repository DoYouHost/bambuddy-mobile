import 'package:flutter/material.dart';

import 'wear_theme.dart';

/// A message that stays until replaced, so it may run to a second line.
const wearErrorMaxChars = 80;

/// A message in a `WearToast`, gone in three seconds. Four lines of the
/// inscribed rectangle on the smallest face hold ~90 characters (~142 dp wide,
/// ~6 dp a character); this cap only stops a 300-character exception string
/// arriving as a wall of grey.
const wearToastMaxChars = 100;

TextStyle wearErrorStyle(BuildContext context) =>
    WearText.small.copyWith(color: Theme.of(context).colorScheme.error);

String wearShortText(String text, {required int max}) =>
    text.length > max ? '${text.substring(0, max)}…' : text;
