import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// `tintBox` is the washed, outlined box behind banners and accent rows. Its
/// default radius is the banners' (seven call sites rely on it); a row that is
/// its own tap target passes its own, and these are the decorations the light
/// row, the Panda Breath row and the tag chip drew by hand before.
void main() {
  for (final t in [
    const DashTokens.dark(bambuddyBrand),
    const DashTokens.light(bambuddyBrand),
  ]) {
    group('${t.brightness.name} tokens', () => _cases(t));
  }
}

void _cases(DashTokens t) {
  BoxDecoration byHand(Color accent, double radius) => BoxDecoration(
    color: accent.withValues(alpha: DashAlpha.faint),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: accent.withValues(alpha: DashAlpha.soft)),
  );

  test('a banner keeps the large radius it always had', () {
    expect(t.tintBox(t.accentBlue), byHand(t.accentBlue, DashRadius.lg));
  });

  test('an accent row draws the box it drew by hand', () {
    expect(
      t.tintBox(t.accentGreen, radius: DashRadius.xl),
      byHand(t.accentGreen, DashRadius.xl),
    );
  });

  test('a chip draws the box it drew by hand', () {
    expect(
      t.tintBox(t.accentGreen, radius: DashRadius.sm),
      byHand(t.accentGreen, DashRadius.sm),
    );
  });

  test('the radius is the only thing that moves', () {
    final banner = t.tintBox(t.accentOrange);
    final row = t.tintBox(t.accentOrange, radius: DashRadius.xl);
    expect(row.color, banner.color);
    expect(row.border, banner.border);
    expect(row.borderRadius, isNot(banner.borderRadius));
  });
}
