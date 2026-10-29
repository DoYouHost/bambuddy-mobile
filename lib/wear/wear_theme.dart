import 'package:material_ui/material_ui.dart';

import 'package:material_color_utilities/material_color_utilities.dart';

import '../core/theme/app_brand.dart' show AccentPreset;
import '../core/theme/dash_theme.dart';

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

/// Corner radius of a row you tap: Wear Material 3's `CornerLarge`, the
/// radius of every button.
const wearRadiusRow = 26.0;

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

const _tintFill = DashAlpha.wash;
const _tintBorder = DashAlpha.strong;

/// The watch type scale, by role rather than by size. A site needing a colour
/// does a `copyWith` on the role, so the size stays decided here — and sizes a
/// component theme can carry are not here at all: a button and an input label
/// get theirs from [wearTheme].
class WearText {
  /// The question on a full-screen confirm: Wear Material 3's `titleMedium`,
  /// 16 sp at weight 550 — Flutter takes weights in hundreds, so 600.
  static const hero = TextStyle(
    fontSize: WearFontSize.hero,
    fontWeight: DashWeight.semibold,
  );

  /// The line under that question: `bodyMedium`, 14 sp at 450, so 400.
  static const message = TextStyle(fontSize: WearFontSize.title);

  /// The header line at the top of a screen's scroll.
  static const title = TextStyle(
    fontSize: WearFontSize.title,
    fontWeight: DashWeight.bold,
  );

  /// A step heading inside a screen (the setup flow's sections).
  static const section = TextStyle(
    fontSize: WearFontSize.title,
    fontWeight: DashWeight.bold,
  );

  /// The name of a thing you can act on — a row, a chip, a button-shaped label.
  static const strong = TextStyle(
    fontSize: WearFontSize.title,
    fontWeight: DashWeight.semibold,
  );

  /// A value the user typed or is about to.
  static const value = TextStyle(fontSize: WearFontSize.title);

  /// Ordinary prose: the sentence under a heading, a readout, a toast, a row's
  /// second line, an error. 12 sp is Play's floor for essential text (WO-V14),
  /// so a quieter line is quieter by colour, never by size.
  static const body = TextStyle(fontSize: WearFontSize.body);

  /// Fine print: a label above a value, a field's hint — never text the user
  /// needs before acting (WO-V14 allows 10 sp only for non-essential text).
  static const fine = TextStyle(fontSize: WearFontSize.fine, color: wearMuted);
}

/// Wear Material 3's `ButtonDefaults` (compose-material3 1.7.1): every button
/// variant is 52 dp tall, fully rounded (26 dp on 52), its content inset by
/// [WearSpace]'s button values, its icon 26 dp (24 on an outlined one, which
/// also adds a 1 dp `Outline` border).
const wearButtonHeight = 52.0;
const wearButtonPadding = EdgeInsets.symmetric(
  horizontal: WearSpace.buttonHorizontal,
  vertical: WearSpace.buttonVertical,
);

/// The label of every button: Wear Material 3's `LabelMedium`, 15 sp at 500.
const wearButtonLabel = TextStyle(
  fontSize: WearFontSize.hero,
  fontWeight: DashWeight.medium,
);

/// A button's second line: Wear Material 3's `LabelSmall`, 13 sp at 500.
const wearButtonSecondaryLabel = TextStyle(
  fontSize: WearFontSize.title,
  fontWeight: DashWeight.medium,
);

/// Dark, black-background theme (OLED-friendly) with larger tap targets.
/// Buttons and input labels take their type from here so the screens stop
/// repeating it. No snackbar theme: a bar pinned to the bottom of a
/// round face is mostly off the glass, and the watch uses `WearToast`.
ThemeData wearTheme([ColorScheme? colorScheme]) {
  final scheme = colorScheme ?? wearSeedScheme(wearGreen);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(wearButtonHeight),
        padding: wearButtonPadding,
        shape: const StadiumBorder(),
        textStyle: wearButtonLabel,
        iconSize: DashIcon.lg,
      ),
    ),
    // The secondary action in a list: a full-width outlined button, not the
    // phone's bare `TextButton` — Wear OS has no such list action.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(wearButtonHeight),
        padding: wearButtonPadding,
        shape: const StadiumBorder(),
        textStyle: wearButtonLabel,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        iconSize: DashIcon.lg,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: WearText.body,
      helperStyle: WearText.fine,
    ),
  );
}

/// A message that stays until replaced, so it may run to a second line.
const wearErrorMaxChars = 80;

/// A message in a `WearToast`, gone in three seconds. Four lines of the
/// inscribed rectangle on the smallest face hold ~90 characters (~142 dp wide,
/// ~6 dp a character); this cap only stops a 300-character exception string
/// arriving as a wall of grey.
const wearToastMaxChars = 100;

TextStyle wearErrorStyle(BuildContext context) =>
    WearText.body.copyWith(color: Theme.of(context).colorScheme.error);

String wearShortText(String text, {required int max}) =>
    text.length > max ? '${text.substring(0, max)}…' : text;

/// The watch's own accent, drawn when neither the phone nor the face gives one.
const AccentPreset wearGreen = (
  seed: Colors.green,
  variant: DynamicSchemeVariant.tonalSpot,
);

/// Wear Material 3's dark colour roles (compose-material3 1.7.1 `ColorTokens`)
/// on the tonal palettes of [accent]. The phone's `ColorScheme.fromSeed` puts
/// the roles on other tones — a filled button's label on tone 20 rather than
/// 10, which on the watch read as green text instead of a dark one.
ColorScheme wearSeedScheme(AccentPreset accent) {
  // The palettes `ColorScheme.fromSeed` draws from; only the tones differ.
  final source = Hct.fromInt(accent.seed.toARGB32());
  // The phone sends only these two (`accentPresets`, and tonalSpot for
  // "System"); anything else draws as tonalSpot.
  final scheme = accent.variant == DynamicSchemeVariant.monochrome
      ? SchemeMonochrome(sourceColorHct: source, isDark: true, contrastLevel: 0)
      : SchemeTonalSpot(sourceColorHct: source, isDark: true, contrastLevel: 0);
  Color tone(TonalPalette p, int t) => Color(p.get(t));
  return ColorScheme(
    brightness: Brightness.dark,
    primary: tone(scheme.primaryPalette, 90),
    onPrimary: tone(scheme.primaryPalette, 10),
    primaryContainer: tone(scheme.primaryPalette, 30),
    onPrimaryContainer: tone(scheme.primaryPalette, 95),
    secondary: tone(scheme.secondaryPalette, 90),
    onSecondary: tone(scheme.secondaryPalette, 10),
    secondaryContainer: tone(scheme.secondaryPalette, 30),
    onSecondaryContainer: tone(scheme.secondaryPalette, 95),
    tertiary: tone(scheme.tertiaryPalette, 90),
    onTertiary: tone(scheme.tertiaryPalette, 10),
    tertiaryContainer: tone(scheme.tertiaryPalette, 30),
    onTertiaryContainer: tone(scheme.tertiaryPalette, 95),
    error: tone(scheme.errorPalette, 80),
    onError: tone(scheme.errorPalette, 10),
    errorContainer: tone(scheme.errorPalette, 30),
    onErrorContainer: tone(scheme.errorPalette, 95),
    // `Background` is Neutral0: the watch draws on black.
    surface: Colors.black,
    onSurface: tone(scheme.neutralPalette, 95),
    onSurfaceVariant: tone(scheme.neutralVariantPalette, 80),
    outline: tone(scheme.neutralVariantPalette, 60),
    outlineVariant: tone(scheme.neutralVariantPalette, 40),
    surfaceContainerLow: tone(scheme.neutralPalette, 15),
    surfaceContainer: tone(scheme.neutralPalette, 20),
    surfaceContainerHigh: tone(scheme.neutralPalette, 30),
  );
}
