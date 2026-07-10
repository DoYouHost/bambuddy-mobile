import 'package:flutter/material.dart';

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
  final Color textSecondary;
  final Color textTertiary;

  /// Vivid brand green — gauge fills, dots, ON states, progress bars.
  final Color accentGreen;

  /// Green used for text/icons on cards (deepened in light mode for contrast).
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
        textSecondary = const Color(0x8CF2F4EF),
        textTertiary = const Color(0x66F2F4EF),
        accentGreen = const Color(0xFF5FE08A),
        accentGreenInk = const Color(0xFF5FE08A),
        accentOrange = const Color(0xFFFF9F5C),
        accentBlue = const Color(0xFF4FA6F7),
        danger = const Color(0xFFFF6B6B),
        gaugeTrack = const Color(0x10FFFFFF),
        hairline = const Color(0x14FFFFFF),
        dottedRule = const Color(0x24FFFFFF),
        navBar = const Color(0x59000000);

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
        textSecondary = const Color(0x99202318),
        textTertiary = const Color(0x66202318),
        accentGreen = const Color(0xFF34C46E),
        accentGreenInk = const Color(0xFF1F8F4D),
        accentOrange = const Color(0xFFE07C36),
        accentBlue = const Color(0xFF2C7FE0),
        danger = const Color(0xFFD64545),
        gaugeTrack = const Color(0x14000000),
        hairline = const Color(0x14000000),
        dottedRule = const Color(0x1F000000),
        navBar = const Color(0x0A000000);
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
AppBar dashAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  Widget? leading,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
}) {
  final t = DashTokens.of(context);
  return AppBar(
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
