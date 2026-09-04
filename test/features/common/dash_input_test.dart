import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/dash_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

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

  /// The picker field seven call sites share. What each of them depends on is
  /// the same three things: which of value and placeholder is showing, that a
  /// placeholder is visibly not a value, and that the clear button exists only
  /// while there is something to clear.
  group('dashPickerField', () {
    Future<void> pump(
      WidgetTester tester, {
      String? value,
      ({String id, VoidCallback onPressed})? clear,
    }) =>
        tester.pumpWidget(plApp(Builder(
          builder: (context) => Scaffold(
            body: dashPickerField(
              context,
              id: 'test.field',
              label: 'Label',
              placeholder: 'Nothing picked',
              value: value,
              clear: clear,
              onTap: () {},
            ),
          ),
        )));

    Color colourOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    testWidgets('an empty value shows the placeholder, and shows that it is one',
        (tester) async {
      await pump(tester);
      final t = DashTokens.of(tester.element(find.text('Nothing picked')));

      expect(colourOf(tester, 'Nothing picked'), t.textTertiary);
    });

    testWidgets('a value reads as one, in the primary ink', (tester) async {
      await pump(tester, value: 'Bambu PLA Basic');
      final t = DashTokens.of(tester.element(find.text('Bambu PLA Basic')));

      expect(colourOf(tester, 'Bambu PLA Basic'), t.textPrimary);
      expect(find.text('Nothing picked'), findsNothing);
    });

    testWidgets('the clear button appears only once something is picked',
        (tester) async {
      var cleared = 0;
      final clear = (id: 'test.field.clear', onPressed: () => cleared++);

      await pump(tester, clear: clear);
      expect(find.byIcon(Icons.clear), findsNothing);

      await pump(tester, value: 'Bambu PLA Basic', clear: clear);
      await tester.tap(find.byIcon(Icons.clear));

      expect(cleared, 1);
    });

    testWidgets('a field with no clear callback never grows one',
        (tester) async {
      await pump(tester, value: 'Bambu PLA Basic');

      expect(find.byIcon(Icons.clear), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });
  });
}
