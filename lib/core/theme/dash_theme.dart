import 'package:flutter/material.dart';

import '../diagnostics/log_tag.dart';

/// Visual design tokens for the modernized "2a" screens (Printers, Queue,
/// Archive, Maintenance, Filaments) and the shared bottom navigation.
///
/// The reference design is a dark, near-black screen with a vivid green accent
/// and layered translucent cards. This app follows the system theme, so tokens
/// resolve per [Brightness]: dark mode reproduces the design hex values 1:1;
/// light mode maps the same layout onto light surfaces with accent hues
/// deepened for contrast. Layout/typography/radii are identical in both — only
/// colors differ.
///
/// Font families are bundled (see pubspec): [fontUi] for labels/titles,
/// [fontMono] for all numeric/technical values.
class DashTokens {
  const DashTokens({
    required this.brightness,
    required this.backgroundGradient,
    required this.cardGradient,
    required this.cardBorder,
    required this.subCard,
    required this.subCardBorder,
    required this.groupCard,
    required this.groupCardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentGreen,
    required this.accentGreenInk,
    required this.accentOrange,
    required this.accentBlue,
    required this.danger,
    required this.gaugeTrack,
    required this.hairline,
    required this.dottedRule,
    required this.navBar,
    required this.overlaySurface,
    required this.overlayBorder,
  });

  final Brightness brightness;

  /// Full-screen backdrop behind the card list.
  final Gradient backgroundGradient;

  /// Main card fill + its border.
  final Gradient cardGradient;
  final Color cardBorder;

  /// Small tiles inside a card (gauges, fans, status bar).
  final Color subCard;
  final Color subCardBorder;

  /// Grouping container (AMS / external spool block).
  final Color groupCard;
  final Color groupCardBorder;

  final Color textPrimary;

  /// The two muted inks, and the reason they are as opaque as they are.
  ///
  /// Both carry ordinary body text — `label` and `micro` are 11-12 px, a hint
  /// inside a field is [textTertiary] — so both have to clear WCAG AA's 4.5:1
  /// against the surface they sit on, and the surface is the *lightest* card a
  /// theme has, not its background. At the 0x66 they used to share, the muted
  /// caption on a light card measured 2.4:1 and the same caption in the dark
  /// theme 3.5:1: legible to whoever picked them, and not to a reader who needs
  /// the contrast.
  ///
  /// `theme_contrast_test.dart` computes the ratios from these very values, so
  /// a palette edit that drops one below the floor fails there rather than in a
  /// store review. It measures against every surface a theme can put behind
  /// text and keeps the worst — which for a dark ink is the *darkest* surface,
  /// the bare background corner, and not the white card that flatters it.
  final Color textSecondary;
  final Color textTertiary;

  /// Vivid brand green — gauge fills, dots, ON states, progress bars.
  final Color accentGreen;

  /// Green used for text/icons on cards (deepened in light mode for contrast).
  /// The accent as **ink** — text and icons on a pale surface, which is what
  /// every `TextButton` in the app is painted with, and `colorScheme.primary`.
  /// Never a fill: the solid green is [accentGreen], and it keeps its vivid
  /// swatch precisely because this one had to darken instead.
  ///
  /// Held to the same 4.5:1 as body text and for the same reason — a dialog's
  /// "Cancel" is text. The light theme's #1F8F4D read 3.45:1 against the palest
  /// card, which is a button label nobody with low vision could pick out.
  final Color accentGreenInk;

  /// Nozzle/heat orange and chamber/cooling blue (gauge fills + accents).
  final Color accentOrange;
  final Color accentBlue;

  /// Warning/low/error accent (e.g. LOW filament, urgent maintenance, delete).
  final Color danger;

  /// Circular gauge / progress-bar background track.
  final Color gaugeTrack;

  /// Thin separators (top borders).
  final Color hairline;

  /// Dotted separators between list rows.
  final Color dottedRule;

  /// Bottom navigation bar background.
  final Color navBar;

  /// Opaque surface for floating overlays (dialogs, popup menus, snackbars,
  /// bottom sheets) — unlike [cardGradient]/[subCard], which are translucent
  /// washes meant to sit on [backgroundGradient], these overlays float above
  /// whatever route is behind them and need a solid fill to stay legible.
  final Color overlaySurface;
  final Color overlayBorder;

  static const String fontUi = 'Manrope';
  static const String fontMono = 'JetBrainsMono';

  bool get isDark => brightness == Brightness.dark;

  factory DashTokens.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const DashTokens.dark()
          : const DashTokens.light();

  const DashTokens.dark()
      : brightness = Brightness.dark,
        backgroundGradient = const RadialGradient(
          center: Alignment(-0.6, -1),
          radius: 1.4,
          colors: [Color(0xFF131A12), Color(0xFF07090A), Color(0xFF050605)],
          stops: [0.0, 0.55, 1.0],
        ),
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x0DFFFFFF), Color(0x04FFFFFF)],
        ),
        cardBorder = const Color(0x12FFFFFF),
        subCard = const Color(0x08FFFFFF),
        subCardBorder = const Color(0x0DFFFFFF),
        groupCard = const Color(0x06FFFFFF),
        groupCardBorder = const Color(0x0FFFFFFF),
        textPrimary = const Color(0xFFFBFCF9),
        textSecondary = const Color(0xB0F2F4EF),
        textTertiary = const Color(0x88F2F4EF),
        accentGreen = const Color(0xFF5FE08A),
        accentGreenInk = const Color(0xFF5FE08A),
        accentOrange = const Color(0xFFFF9F5C),
        accentBlue = const Color(0xFF4FA6F7),
        danger = const Color(0xFFFF6B6B),
        gaugeTrack = const Color(0x10FFFFFF),
        hairline = const Color(0x14FFFFFF),
        dottedRule = const Color(0x24FFFFFF),
        navBar = const Color(0x59000000),
        overlaySurface = const Color(0xFF0E1310),
        overlayBorder = const Color(0x24FFFFFF);

  const DashTokens.light()
      : brightness = Brightness.light,
        backgroundGradient = const RadialGradient(
          center: Alignment(-0.6, -1),
          radius: 1.4,
          colors: [Color(0xFFEAF2E7), Color(0xFFF6F8F4), Color(0xFFFDFEFC)],
          stops: [0.0, 0.55, 1.0],
        ),
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F7F3)],
        ),
        cardBorder = const Color(0x14000000),
        subCard = const Color(0x05000000),
        subCardBorder = const Color(0x0F000000),
        groupCard = const Color(0x04000000),
        groupCardBorder = const Color(0x12000000),
        textPrimary = const Color(0xFF10130E),
        textSecondary = const Color(0xC4202318),
        textTertiary = const Color(0xAC202318),
        accentGreen = const Color(0xFF34C46E),
        accentGreenInk = const Color(0xFF18733D),
        accentOrange = const Color(0xFFE07C36),
        accentBlue = const Color(0xFF2C7FE0),
        danger = const Color(0xFFD64545),
        gaugeTrack = const Color(0x14000000),
        hairline = const Color(0x14000000),
        dottedRule = const Color(0x1F000000),
        navBar = const Color(0x0A000000),
        overlaySurface = const Color(0xFFF6F8F4),
        overlayBorder = const Color(0x14000000);
}

/// Full-screen gradient backdrop for a "2a" screen. Wrap a transparent
/// [Scaffold] in this so the gradient shows through the app bar and body.
class DashBackground extends StatelessWidget {
  const DashBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: t.backgroundGradient),
      child: child,
    );
  }
}

/// Transparent app bar with the design's bold, tightly-tracked title. Use inside
/// a [DashBackground] + transparent [Scaffold].
///
/// Named `chrome.appbar` for the diagnostic log. The back button is built by
/// [AppBar] itself, so it cannot be tagged directly without taking over the
/// "is there anything to go back to" logic and shifting the title on screens
/// with no back button; naming the bar reaches it through inheritance, and
/// tagged actions inside keep their own names.
/// Names a hand-built [AppBar] for the diagnostic log without restyling it.
///
/// Screens that cannot use [dashAppBar] (the camera, the G-code viewer, the QR
/// scanner — all dark by design) still get a framework-built back button, and
/// that button is unreachable by a tag of its own. Wrapping the whole bar names
/// it by inheritance. The bar's own [AppBar.preferredSize] is kept, so a bar
/// with a `bottom:` is not clipped.
PreferredSizeWidget loggedAppBar(AppBar bar) => PreferredSize(
      preferredSize: bar.preferredSize,
      child: logTag('chrome.appbar', bar),
    );

PreferredSizeWidget dashAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  Widget? leading,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
}) {
  final t = DashTokens.of(context);
  final bar = AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    iconTheme: IconThemeData(color: t.textPrimary),
    title: Text(
      title,
      style: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: t.textPrimary,
      ),
    ),
    actions: actions,
    bottom: bottom,
  );
  return PreferredSize(
    preferredSize: bar.preferredSize,
    child: logTag('chrome.appbar', bar),
  );
}

/// Small rounded status pill (e.g. "3 w kolejce", "1 PILNE"). Tinted with an
/// accent; used in screen headers.
class DashPill extends StatelessWidget {
  const DashPill({
    super.key,
    required this.label,
    required this.accent,
    this.accentInk,
    this.leadingDot = false,
    this.icon,
  });

  final String label;
  final Color accent;
  final Color? accentInk;
  final bool leadingDot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = accentInk ?? accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingDot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared field chrome for form screens: rounded [DashTokens.subCard] fill
/// with a hairline border, turning [DashTokens.accentGreen] on focus. Same
/// look as the inventory spool form's decoration.
InputDecoration dashFieldDecoration(
  DashTokens t, {
  String? labelText,
  String? hintText,
  String? helperText,
  String? errorText,
  String? suffixText,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) {
  final radius = BorderRadius.circular(14);
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: color, width: width));
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: t.subCard,
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    labelStyle: TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: t.textSecondary,
    ),
    floatingLabelStyle: TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: t.accentGreenInk,
    ),
    hintStyle: TextStyle(fontFamily: DashTokens.fontUi, color: t.textTertiary),
    helperStyle: TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 11,
      color: t.textTertiary,
    ),
    suffixStyle: TextStyle(
      fontFamily: DashTokens.fontMono,
      fontSize: 11.5,
      color: t.textTertiary,
    ),
    border: border(t.subCardBorder),
    enabledBorder: border(t.subCardBorder),
    focusedBorder: border(t.accentGreen, 1.5),
    errorBorder: border(t.danger),
    focusedErrorBorder: border(t.danger, 1.5),
  );
}

/// Primary CTA button style for Dash screens: filled vivid green with dark
/// ink, matching the queue screen's "start next" FAB.
ButtonStyle dashPrimaryButtonStyle(DashTokens t) => FilledButton.styleFrom(
      backgroundColor: t.accentGreen,
      foregroundColor: const Color(0xFF0A0C08),
      disabledBackgroundColor: t.accentGreen.withValues(alpha: 0.35),
      disabledForegroundColor: const Color(0xFF0A0C08).withValues(alpha: 0.5),
      textStyle: const TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      // Horizontal padding matters for auto-width buttons (dialog actions);
      // full-width CTAs center their label regardless, so this is safe there.
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

/// Ink for text/icons painted directly on a solid [DashTokens.accentGreen]
/// fill — fixed regardless of brightness, since the green fill itself is a
/// constant vivid swatch in both themes.
const Color _onAccentGreenFill = Color(0xFF0A0C08);

/// App-wide [ThemeData] for [brightness], built from [DashTokens] so every
/// stock Material widget (dialogs, popup menus, bottom sheets, chips,
/// snackbars, switches, ...) matches the "2a" screens without each call site
/// having to opt in individually. Screens/widgets that already read
/// [DashTokens.of] directly for bespoke layouts are unaffected — this only
/// changes the *fallback* look of un-migrated stock widgets.
ThemeData buildDashThemeData(Brightness brightness) {
  final t = brightness == Brightness.dark
      ? const DashTokens.dark()
      : const DashTokens.light();

  final colorScheme = ColorScheme.fromSeed(
    seedColor: t.accentGreen,
    brightness: brightness,
  ).copyWith(
    primary: t.accentGreenInk,
    onPrimary: _onAccentGreenFill,
    secondary: t.accentBlue,
    error: t.danger,
    onError: Colors.white,
    surface: t.overlaySurface,
    onSurface: t.textPrimary,
    surfaceContainerHighest: t.overlaySurface,
    surfaceContainerHigh: t.overlaySurface,
    surfaceContainer: t.overlaySurface,
    onSurfaceVariant: t.textSecondary,
    outline: t.subCardBorder,
    outlineVariant: t.hairline,
  );

  final baseText = ThemeData(brightness: brightness).textTheme.apply(
        fontFamily: DashTokens.fontUi,
        bodyColor: t.textPrimary,
        displayColor: t.textPrimary,
      );

  final radius14 = BorderRadius.circular(14);
  final radius16 = BorderRadius.circular(16);
  final radius20 = BorderRadius.circular(20);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        t.isDark ? const Color(0xFF07090A) : const Color(0xFFFDFEFC),
    textTheme: baseText,
    primaryTextTheme: baseText,
    iconTheme: IconThemeData(color: t.textSecondary),
    primaryIconTheme: IconThemeData(color: t.textPrimary),
    dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: t.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: t.textPrimary),
      titleTextStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: t.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: t.overlaySurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius16),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.overlaySurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius20,
        side: BorderSide(color: t.overlayBorder),
      ),
      // The filled action button uses the heavy primary style (radius 14);
      // keep it clear of the dialog's rounded corner/border.
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      titleTextStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: t.textPrimary,
      ),
      contentTextStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 14,
        color: t.textSecondary,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.overlaySurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius16,
        side: BorderSide(color: t.overlayBorder),
      ),
      textStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      iconColor: t.textSecondary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.overlaySurface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: t.overlaySurface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: t.overlayBorder),
      ),
      dragHandleColor: t.textTertiary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.overlaySurface,
      contentTextStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 13.5,
        color: t.textPrimary,
      ),
      actionTextColor: t.accentGreenInk,
      shape: RoundedRectangleBorder(
        borderRadius: radius14,
        side: BorderSide(color: t.overlayBorder),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.overlaySurface,
        borderRadius: radius14,
        border: Border.all(color: t.overlayBorder),
      ),
      textStyle: TextStyle(fontFamily: DashTokens.fontUi, color: t.textPrimary),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.textPrimary,
      titleTextStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 12.5,
        color: t.textSecondary,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.subCard,
      selectedColor: t.accentGreen.withValues(alpha: 0.18),
      disabledColor: t.subCard.withValues(alpha: 0.5),
      side: BorderSide(color: t.subCardBorder),
      shape: StadiumBorder(side: BorderSide(color: t.subCardBorder)),
      labelStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: t.accentGreenInk,
      ),
      checkmarkColor: t.accentGreenInk,
      iconTheme: IconThemeData(color: t.textSecondary, size: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? t.accentGreen.withValues(alpha: 0.18)
                : t.subCard),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? t.accentGreenInk
                : t.textSecondary),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? t.accentGreen.withValues(alpha: 0.4)
                : t.subCardBorder)),
        textStyle: const WidgetStatePropertyAll(TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        )),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? t.accentGreen : null),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.accentGreen.withValues(alpha: 0.4)
              : t.subCard),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? t.accentGreen : null),
      checkColor: const WidgetStatePropertyAll(_onAccentGreenFill),
      // subCardBorder (~5% white) is invisible for an interactive control;
      // use the mid-contrast outline Material itself uses (onSurfaceVariant).
      side: BorderSide(color: t.textSecondary, width: 1.5),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.accentGreen
              : t.textTertiary),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accentGreen,
      inactiveTrackColor: t.gaugeTrack,
      thumbColor: t.accentGreen,
      overlayColor: t.accentGreen.withValues(alpha: 0.16),
      valueIndicatorColor: t.overlaySurface,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accentGreen,
      linearTrackColor: t.gaugeTrack,
      circularTrackColor: t.gaugeTrack,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(fontFamily: DashTokens.fontUi, color: t.textPrimary),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.overlaySurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: radius16,
            side: BorderSide(color: t.overlayBorder))),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.overlaySurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: radius16,
            side: BorderSide(color: t.overlayBorder))),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.subCard,
      labelStyle: TextStyle(fontFamily: DashTokens.fontUi, color: t.textSecondary),
      hintStyle: TextStyle(fontFamily: DashTokens.fontUi, color: t.textTertiary),
      border: OutlineInputBorder(
          borderRadius: radius14, borderSide: BorderSide(color: t.subCardBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: radius14, borderSide: BorderSide(color: t.subCardBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: t.accentGreen, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: radius14, borderSide: BorderSide(color: t.danger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius14, borderSide: BorderSide(color: t.danger, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: dashPrimaryButtonStyle(t)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.subCard,
        foregroundColor: t.textPrimary,
        textStyle: const TextStyle(
            fontFamily: DashTokens.fontUi, fontWeight: FontWeight.w700),
        // Match the filled button padding so heights line up when buttons of
        // different kinds sit side by side.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.textPrimary,
        side: BorderSide(color: t.subCardBorder),
        textStyle: const TextStyle(
            fontFamily: DashTokens.fontUi, fontWeight: FontWeight.w700),
        // Match the filled button padding so heights line up when buttons of
        // different kinds sit side by side.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accentGreenInk,
        textStyle: const TextStyle(
            fontFamily: DashTokens.fontUi, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: radius14),
      ),
    ),
    disabledColor: t.textTertiary,
    hintColor: t.textTertiary,
    splashColor: t.accentGreen.withValues(alpha: 0.08),
    highlightColor: t.accentGreen.withValues(alpha: 0.05),
  );
}
