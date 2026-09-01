import 'package:flutter/material.dart';

/// Design tokens and the app theme for the watch, the counterpart of the phone's
/// `DashTokens`/`dashAppTheme`.
///
/// The watch has its own scale on purpose: everything here is read at arm's
/// length on a 1.4" screen, so the phone's sizes are all a step too large and its
/// colour tokens (layered translucent cards on a gradient) mean nothing on an
/// OLED face that has to stay black to save battery.

/// Secondary text on the black face. Bright enough to read, dim enough to say
/// "this is not the thing you came for".
const wearMuted = Colors.white54;

/// Accent for a confirm that destroys something — stopping a print, dropping a
/// server. Every confirmation on the watch is one of those so far, hence the
/// default in `wearConfirm`.
const wearDestructive = Color(0xFFB3261E);

/// The watch type scale, by role rather than by size.
///
/// Reach for a role, not a number: before this, the same heading was 13, 14 and
/// 15 on three screens and the same fine print was 9 in one place and 10 in
/// another, because every site picked its own literal. Where a site needs a
/// colour (a state, an error) it is a `copyWith` on the role, so the size stays
/// decided here.
///
/// Sizes a component theme can carry are not here at all — a text button and an
/// input label get theirs from [wearTheme], so a screen never styles them.
class WearText {
  /// The question on a full-screen confirm: alone on the face, so it gets to be
  /// the largest thing in the app.
  static const hero = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

  /// The header line at the top of a screen's scroll.
  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);

  /// A step heading inside a screen (the setup flow's sections).
  static const section = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);

  /// The name of a thing you can act on — a row, a chip, a button-shaped label.
  static const strong = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  /// A value the user typed or is about to.
  static const value = TextStyle(fontSize: 13);

  /// Ordinary prose: the sentence under a heading, a readout, a toast.
  static const body = TextStyle(fontSize: 12);

  /// The quieter line — a row's second line, an error under a button.
  static const small = TextStyle(fontSize: 11);

  /// Fine print: a label above a value, a field's hint, a consequence warning.
  static const fine = TextStyle(fontSize: 10, color: wearMuted);
}

/// Dark, black-background theme (OLED-friendly) with larger tap targets.
///
/// Anything with a component theme takes its type from here, so the screens stop
/// repeating it: text buttons, filled buttons and input labels. There is no
/// snackbar theme because there are no snackbars: a bar pinned to the bottom of
/// a round face is mostly off the glass, so the watch says it with `WearToast`
/// instead.
ThemeData wearTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.green,
    brightness: Brightness.dark,
  ).copyWith(surface: Colors.black);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: const StadiumBorder(),
        textStyle: WearText.strong,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: WearText.body),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: WearText.body,
      helperStyle: WearText.fine,
    ),
  );
}
