/// The spacing scale: every padding, margin and gap in `lib/` is one of these.
///
/// A 4 dp grid. Before it existed the app had 25 distinct hand-typed values
/// and two side margins (12 and 16) that made a search bar and the card above
/// it end at different x. `spacing_scale_test.dart` refuses a numeric literal
/// where one of these belongs.
abstract final class DashSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Left and right inset of everything that meets the screen edge: cards,
  /// list tiles, search bars, banners, section headers.
  static const double gutter = lg;

  /// Bottom inset of a list under a FAB: the 56 dp button, its 16 dp margin
  /// and one [lg] of air, so the last row can scroll clear of it.
  static const double fabClearance = 88;
}
