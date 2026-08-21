import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/dash_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A `DropdownMenu` builds its own field, so it takes a theme instead of a
  /// decoration — and the two used to be written out separately and drift. They
  /// are now one source; this is the test that says so.
  for (final tokens in [const DashTokens.dark(), const DashTokens.light()]) {
    final name = tokens.isDark ? 'dark' : 'light';

    test('the dropdown theme carries the field chrome ($name)', () {
      final field = dashFieldDecoration(tokens);
      final menu = dashInputTheme(tokens);

      expect(menu.fillColor, field.fillColor);
      expect(menu.labelStyle, field.labelStyle);
      expect(menu.floatingLabelStyle, field.floatingLabelStyle);
      expect(menu.hintStyle, field.hintStyle);
      expect(menu.helperStyle, field.helperStyle);
      expect(menu.border, field.border);
      expect(menu.enabledBorder, field.enabledBorder);
      expect(menu.focusedBorder, field.focusedBorder);
      expect(menu.errorBorder, field.errorBorder);
      expect(menu.focusedErrorBorder, field.focusedErrorBorder);
      expect(menu.isDense, isTrue);
      expect(menu.filled, isTrue);
    });

    test('the form decoration is the same chrome, suffix included ($name)', () {
      final plain = dashFieldDecoration(tokens, suffixText: 'g');
      final shared = dashDecoration(tokens, suffixText: 'g');

      expect(shared.labelStyle, plain.labelStyle);
      expect(shared.suffixStyle, plain.suffixStyle);
      expect(shared.suffixText, 'g');
      expect(shared.focusedBorder, plain.focusedBorder);
    });
  }
}
