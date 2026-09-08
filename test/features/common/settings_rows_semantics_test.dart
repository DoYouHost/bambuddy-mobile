import 'package:bambuddy_mobile/features/common/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The diagnostic identifier and the words a screen reader announces have to
/// land on the **same** semantics node.
///
/// Wrapping the switch row in `MergeSemantics` — the obvious fix for the switch
/// being a second stop for a reader — splits them: the identifier keeps a node
/// of its own and the wording moves to another, so the log can no longer say
/// which row was pressed. Measured against the framework, there is nothing to
/// win either: `SwitchListTile` also leaves the switch its own node.
void main() {
  /// Every semantics node under the app, flattened. Walked from
  /// [WidgetTester.getSemantics] rather than from the binding's semantics
  /// owner, which is deprecated and answers null on the root pipeline owner.
  List<SemanticsData> nodes(WidgetTester tester) {
    final found = <SemanticsData>[];
    void walk(SemanticsNode node) {
      found.add(node.getSemanticsData());
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(tester.getSemantics(find.byType(MaterialApp)));
    return found;
  }

  testWidgets('one node carries both the log id and the row wording', (
    tester,
  ) async {
    // Disposed inside the body: `addTearDown` runs after the check that no
    // handle is left open, so the test fails on the handle rather than on what
    // it was asserting.
    final handle = tester.ensureSemantics();

    await pumpPhone(
      tester,
      Scaffold(
        body: SettingsCard(
          rows: [
            SettingsSwitchRow(
              tag: 'settings.row',
              title: 'Keep the bed warm',
              subtitle: 'Between two chamber-heated prints',
              value: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tagged = nodes(
      tester,
    ).where((n) => n.identifier == 'settings.row').single;
    expect(
      tagged.label,
      allOf(contains('Keep the bed warm'), contains('chamber-heated')),
      reason: 'the id sits on the node carrying the wording, not beside it',
    );

    handle.dispose();
  });

  testWidgets('a slider announces what it sets, not a bare number', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pumpPhone(
      tester,
      Scaffold(
        body: SettingsCard(
          rows: [
            SettingsSlider(
              tag: 'settings.slider',
              label: 'Chamber wait limit: 15min',
              bubble: '15min',
              value: 900,
              min: 60,
              max: 3600,
              step: 60,
              enabled: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // `Slider` always keeps a node of its own, so the row's words only reach a
    // reader through `semanticFormatterCallback`.
    final slider = nodes(tester).where((n) => n.value.isNotEmpty).single;
    expect(slider.value, 'Chamber wait limit: 15min');
    expect(slider.label, '15min', reason: 'the value indicator, not raw 900');

    handle.dispose();
  });
}
