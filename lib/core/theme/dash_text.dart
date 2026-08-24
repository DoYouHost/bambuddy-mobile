import 'package:flutter/material.dart';

import 'dash_theme.dart';

/// The app's type scale.
///
/// Before this existed every screen assembled its own [TextStyle]: 439 literals
/// in 188 shapes, with sizes 11 through 26 in half-point steps that no design
/// decision ever asked for. The roles below are those shapes rounded onto eight
/// UI steps (11, 12, 13, 14, 16, 18, 20, 26) and five mono ones (11, 13, 16,
/// 18, 26), each with the colour it carried in the overwhelming majority of its
/// uses.
///
/// A role that needs another colour takes one: `t.body.copyWith(color:
/// t.danger)`. That is the only part of a style a screen should still be
/// deciding — a size or a weight that no role covers is a sign the design grew
/// a step, and the step belongs here rather than in the screen.
extension DashTextStyles on DashTokens {
  // ── Display: readouts a room away from the phone ──────────────────────────

  TextStyle get displayLg => _ui(26, FontWeight.w700, textPrimary);
  TextStyle get display => _ui(20, FontWeight.w800, textPrimary);

  // ── Titles ────────────────────────────────────────────────────────────────

  TextStyle get titleLg => _ui(18, FontWeight.w800, textPrimary);
  TextStyle get titleMd => _ui(16, FontWeight.w700, textPrimary);
  TextStyle get titleSm => _ui(14, FontWeight.w700, textPrimary);

  // ── Body ──────────────────────────────────────────────────────────────────

  /// The default for anything a user reads rather than scans.
  TextStyle get bodyStrong => _ui(14, FontWeight.w600, textPrimary);
  TextStyle get body => _ui(13, FontWeight.w600, textPrimary);

  /// Section headings inside a card — bold, but not a title.
  TextStyle get bodyBold => _ui(13, FontWeight.w700, textSecondary);
  TextStyle get bodySoft => _ui(13, FontWeight.w500, textSecondary);
  TextStyle get bodyPlain => _ui(13, FontWeight.w400, textSecondary);

  // ── Labels and the small print ────────────────────────────────────────────

  TextStyle get label => _ui(12, FontWeight.w600, textTertiary);
  TextStyle get labelSoft => _ui(12, FontWeight.w400, textTertiary);
  TextStyle get micro => _ui(11, FontWeight.w600, textTertiary);
  TextStyle get microSoft => _ui(11, FontWeight.w400, textTertiary);

  // ── Monospace: numbers that must not dance as they tick ───────────────────

  TextStyle get monoDisplay => _mono(26, FontWeight.w700, textPrimary);
  TextStyle get monoHeadline => _mono(18, FontWeight.w700, textPrimary);
  TextStyle get monoTitle => _mono(16, FontWeight.w800, textPrimary);
  TextStyle get monoValue => _mono(13, FontWeight.w600, textPrimary);
  TextStyle get monoLabel => _mono(11, FontWeight.w600, textTertiary);
  TextStyle get monoMicro => _mono(11, FontWeight.w400, textTertiary);

  TextStyle _ui(double size, FontWeight weight, Color color) => TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  TextStyle _mono(double size, FontWeight weight, Color color) => TextStyle(
        fontFamily: DashTokens.fontMono,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
}
