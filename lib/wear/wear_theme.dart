import 'package:flutter/material.dart';

/// Design tokens and the app theme for the watch, the counterpart of the phone's
/// `DashTokens`/`dashAppTheme`. Its own scale on purpose: this is read at arm's
/// length on a 1.4" screen, and the phone's layered translucent cards mean
/// nothing on an OLED face that stays black to save battery.

/// Secondary text on the black face. Bright enough to read, dim enough to say
/// "this is not the thing you came for".
const wearMuted = Colors.white54;

/// Foreground of something deliberately inert — a placeholder standing in for a
/// button that is not on offer. A step brighter than [wearMuted], which reads
/// as fine print rather than as a label at button size.
const wearInert = Colors.white70;

/// Accent for a confirm that destroys something — stopping a print, dropping a
/// server. Every confirmation on the watch is one of those so far, hence the
/// default in `wearConfirm`.
const wearDestructive = Color(0xFFB3261E);

/// Words on a fault card. [wearDestructive] is what the card is *tinted* with
/// and too dark to then read on, so the text steps up to a red that survives
/// being small on a dark fill.
const wearFaultText = Color(0xFFE57373);

/// A row lifted off the black so it reads as one thing you can tap.
const wearSurface = Color(0xFF1C1C1E);

/// A step higher: what sits beside or inside an accent control and must not
/// compete with it — a progress track, a cancel next to a red confirm.
const wearSurfaceHigh = Color(0xFF2A2A2C);

/// Over the whole face while a command is in flight.
const wearScrim = Color(0x99000000);

/// Corner radius of a tinted pill or card — the status chip, a fault.
///
/// Also the floor Google Play's Wear OS review applies to anything row-shaped,
/// which is why the fault card came up from the 14 it was written with.
const wearRadiusCard = 16.0;

/// Corner radius of a row you tap. Rounder than a card on purpose: it is the
/// only thing on the watch that answers a touch, and the shape is what says so.
const wearRadiusRow = 20.0;

/// A surface tinted with the colour of whatever it is reporting: a low-alpha
/// fill, a border of the same colour at a strength that survives the OLED black,
/// and the accent left to the caller for its text. The alphas are the status
/// chip's, which are the pair that was tuned against a real face.
BoxDecoration wearTintedBox(Color accent, {double radius = wearRadiusCard}) =>
    BoxDecoration(
      color: accent.withValues(alpha: _tintFill),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: _tintBorder)),
    );

const _tintFill = 0.15;
const _tintBorder = 0.6;

/// The watch type scale, by role rather than by size. A site needing a colour
/// does a `copyWith` on the role, so the size stays decided here — and sizes a
/// component theme can carry are not here at all: a text button and an input
/// label get theirs from [wearTheme].
class WearText {
  /// The question on a full-screen confirm — alone on the face, so the
  /// largest thing in the app.
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

/// Dark, black-background theme (OLED-friendly) with larger tap targets. Text
/// buttons, filled buttons and input labels take their type from here so the
/// screens stop repeating it. No snackbar theme: a bar pinned to the bottom of a
/// round face is mostly off the glass, and the watch uses `WearToast`.
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
