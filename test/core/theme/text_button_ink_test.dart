import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app theme already paints every `TextButton` with `accentGreenInk`, so
/// the `TextButton.styleFrom(foregroundColor: t.accentGreenInk)` that nine call
/// sites carried was the theme restated. Nothing in the suite rendered a button
/// colour before this file, which is why dropping the overrides had no way of
/// failing anything — the removal is only safe as long as this holds.
void main() {
  Color? inkOf(WidgetTester tester) => tester
      .widget<RichText>(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(RichText),
        ),
      )
      .text
      .style
      ?.color;

  Future<void> pumpButton(
    WidgetTester tester,
    Brightness brightness, {
    ButtonStyle? style,
    VoidCallback? onPressed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDashThemeData(brightness),
        home: Scaffold(
          body: TextButton(
            style: style,
            onPressed: onPressed,
            child: const Text('Zapisz'),
          ),
        ),
      ),
    );
    // Material animates the label colour, so a rebuild that swaps enabled for
    // disabled still reads the old ink on the first frame.
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    final tokens = brightness == Brightness.dark
        ? const DashTokens.dark()
        : const DashTokens.light();

    group('${brightness.name} theme', () {
      testWidgets('a bare TextButton is painted with accentGreenInk', (
        tester,
      ) async {
        await pumpButton(tester, brightness, onPressed: () {});

        expect(inkOf(tester), tokens.accentGreenInk);
      });

      // A disabled button drops to the Material default in both spellings: an
      // explicit `foregroundColor` with no `disabledForegroundColor` beside it
      // resolves to null while disabled and falls through exactly as the theme
      // does. That is the state the four save actions are in while a submit is
      // in flight, so it is the state the removal had to match.
      testWidgets('the dropped override changed neither state', (tester) async {
        await pumpButton(tester, brightness, onPressed: () {});
        final bareEnabled = inkOf(tester);
        await pumpButton(tester, brightness);
        final bareDisabled = inkOf(tester);

        final override = TextButton.styleFrom(
          foregroundColor: tokens.accentGreenInk,
        );
        await pumpButton(tester, brightness, style: override, onPressed: () {});
        expect(inkOf(tester), bareEnabled);
        await pumpButton(tester, brightness, style: override);
        expect(inkOf(tester), bareDisabled);
        expect(bareDisabled, isNot(bareEnabled));
      });
    });
  }

  group('dashSaveAction', () {
    testWidgets('goes dead while a submit is in flight', (tester) async {
      var taps = 0;
      Widget host(bool busy) => MaterialApp(
        theme: buildDashThemeData(Brightness.dark),
        home: Scaffold(
          body: dashSaveAction(
            id: 'user_form.save',
            label: 'Zapisz',
            busy: busy,
            onPressed: () => taps++,
          ),
        ),
      );

      await tester.pumpWidget(host(false));
      await tester.tap(find.byType(TextButton));
      expect(taps, 1);

      await tester.pumpWidget(host(true));
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      expect(taps, 1, reason: 'a second tap must not post the form again');
    });

    testWidgets('carries the identifier the log names it by', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDashThemeData(Brightness.dark),
          home: Scaffold(
            body: dashSaveAction(
              id: 'group_form.save',
              label: 'Zapisz',
              busy: false,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.bySemanticsIdentifier('group_form.save'), findsOneWidget);
      handle.dispose();
    });
  });
}
