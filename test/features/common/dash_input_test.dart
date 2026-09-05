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
    var opened = 0;
    setUp(() => opened = 0);

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
              onTap: () => opened++,
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

    testWidgets('the clear button appears only once something is picked, and '
        'takes the tap without opening the picker under it', (tester) async {
      var cleared = 0;
      final clear = (id: 'test.field.clear', onPressed: () => cleared++);

      await pump(tester, clear: clear);
      expect(find.byIcon(Icons.clear), findsNothing);

      await pump(tester, value: 'Bambu PLA Basic', clear: clear);
      await tester.tap(find.byIcon(Icons.clear));

      expect(cleared, 1);
      // A control inside a control: the inner one has to win in its own box,
      // or clearing the field would open the picker it just emptied.
      expect(opened, 0);
    });

    testWidgets('keyboard focus is visible — the decorator is told it has it',
        (tester) async {
      await pump(tester);
      expect(
        tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused,
        isFalse,
      );

      // What a Tab press does, without depending on what else is on screen.
      Focus.of(tester.element(find.byType(InputDecorator))).requestFocus();
      await tester.pump();

      expect(
        tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused,
        isTrue,
      );
    });

    testWidgets('a field with no clear callback never grows one',
        (tester) async {
      await pump(tester, value: 'Bambu PLA Basic');

      expect(find.byIcon(Icons.clear), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });
  });

  /// The filter combo three screens each built their own way. What they all
  /// depend on: the any-row reads as null, it is what shows when nothing is
  /// picked, and no call site needs a stand-in value to say "no filter".
  group('dashAnyOrOne', () {
    late List<int?> picked;
    setUp(() => picked = []);

    Future<void> pump(WidgetTester tester, {int? selected}) =>
        tester.pumpWidget(plApp(Builder(
          builder: (context) => Scaffold(
            body: dashAnyOrOne<int>(
              context,
              id: 'test.filter',
              anyLabel: 'Any printer',
              selected: selected,
              options: const [(3, 'P1S'), (4, 'X1C')],
              onPick: picked.add,
            ),
          ),
        )));

    String fieldText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('nothing picked shows the any-row, not an empty field',
        (tester) async {
      // The reason no sentinel is needed: `initialSelection: null` resolves
      // against the null row, so the field names the state it is in. A
      // stand-in value was introduced on the belief that it could not.
      await pump(tester);

      expect(fieldText(tester), 'Any printer');
    });

    testWidgets('a set filter shows its own label', (tester) async {
      await pump(tester, selected: 4);

      expect(fieldText(tester), 'X1C');
    });

    testWidgets('choosing a value reports the value', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(DropdownMenu<int?>));
      await settle(tester);
      await tester.tap(find.text('P1S').last);
      await settle(tester);

      expect(picked, [3]);
    });

    testWidgets('choosing the any-row reports null, not a stand-in',
        (tester) async {
      // The half every caller depends on: one "no filter" state, so a screen
      // never has to map a magic value back before writing its query.
      await pump(tester, selected: 4);
      await tester.tap(find.byType(DropdownMenu<int?>));
      await settle(tester);
      await tester.tap(find.text('Any printer').last);
      await settle(tester);

      expect(picked, [null]);
    });

    testWidgets('every value row records under one id, the any-row its own',
        (tester) async {
      // Labels are names people gave things and stay out of the log, so which
      // row it was is deliberately not recoverable — only that it was a row.
      await pump(tester);
      await tester.tap(find.byType(DropdownMenu<int?>));
      await settle(tester);

      expect(
        find.bySemanticsLabel(RegExp('.*')).evaluate().isNotEmpty,
        isTrue,
        reason: 'the menu opened',
      );
      final ids = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((w) => w.properties.identifier)
          .whereType<String>()
          .where((id) => id.startsWith('test.filter'))
          .toSet();
      expect(ids, containsAll(['test.filter.any', 'test.filter.option']));
    });
  });
}
