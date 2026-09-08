import 'package:bambuddy_mobile/features/common/button_pair.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The pair sits side by side only while both labels fit on one line, and that
/// is decided by measuring — not by a width breakpoint, which is the version
/// that looks right until someone changes their system text size.
void main() {
  Future<void> pumpPair(
    WidgetTester tester, {
    required double width,
    double textScale = 1.0,
    String primaryLabel = 'Add',
    String secondaryLabel = 'Restore',
  }) => pumpPhone(
    tester,
    Scaffold(
      body: Center(
        // copyWith on the ambient data, never a fresh MediaQueryData: a bare
        // one drops the window size and the layout collapses to nothing.
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: SizedBox(
              width: width,
              child: ButtonPair(
                primaryLabel: primaryLabel,
                secondaryLabel: secondaryLabel,
                primary: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(primaryLabel),
                  onPressed: () {},
                ),
                secondary: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: Text(secondaryLabel),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The button box around [label]. `find.byType` matches the runtime type
  /// exactly, so the abstract [ButtonStyleButton] needs a predicate.
  Rect rectOf(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        )
        .first,
  );

  testWidgets('wide enough: one row, both buttons the same width', (
    tester,
  ) async {
    await pumpPair(tester, width: 400);

    final add = rectOf(tester, 'Add');
    final restore = rectOf(tester, 'Restore');
    expect(add.top, restore.top, reason: 'same row');
    expect(add.width, restore.width, reason: 'Expanded splits it evenly');
    expect(add.right, lessThan(restore.left), reason: 'primary comes first');
  });

  testWidgets('too narrow: stacked, both spanning the full width', (
    tester,
  ) async {
    await pumpPair(tester, width: 200);

    final add = rectOf(tester, 'Add');
    final restore = rectOf(tester, 'Restore');
    expect(add.left, restore.left, reason: 'stacked, not ragged');
    expect(add.width, 200, reason: 'full width, not hugging the label');
    expect(restore.width, 200);
    expect(add.bottom, lessThanOrEqualTo(restore.top));
  });

  testWidgets('a larger system text size stacks a pair that fitted', (
    tester,
  ) async {
    // The whole reason the decision is measured rather than read off a
    // breakpoint: the width did not change, the text did.
    await pumpPair(tester, width: 400);
    expect(rectOf(tester, 'Add').top, rectOf(tester, 'Restore').top);

    await pumpPair(tester, width: 400, textScale: 2.5);
    expect(
      rectOf(tester, 'Add').top,
      lessThan(rectOf(tester, 'Restore').top),
      reason: 'the labels no longer fit beside each other',
    );
  });

  testWidgets('a long label stacks the pair at a width a short one fits', (
    tester,
  ) async {
    const long = 'Przywróć ustawienia domyślne konserwacji';
    await pumpPair(tester, width: 400, secondaryLabel: long);

    expect(rectOf(tester, 'Add').left, rectOf(tester, long).left);
  });
}
