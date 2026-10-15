import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Play's WO-V2 (touch targets ≥ 48 dp) read the way Wear OS's own scaling lists
/// meet it: the list shrinks a row near the edge on purpose, so each target is
/// checked where it is pressed — scrolled to the middle of the face, which
/// auto-centering lets every item reach.
///
/// The measuring is Flutter's own `androidTapTargetGuideline`, narrowed to the
/// one target in the middle. Shared with `patrol_test/`; both need
/// `tester.ensureSemantics()`.
Future<void> expectTapTargetsWhereTheyRest(WidgetTester tester) async {
  final labels = {
    for (final node in find.semantics.byPredicate(_tappable).evaluate())
      node.label,
  };
  expect(labels, isNotEmpty, reason: 'nothing tappable on screen');
  for (final label in labels) {
    // Offstage too: a row in the list's cache extent, below the glass.
    final target = find.bySemanticsLabel(label, skipOffstage: false).first;
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pump();
    await expectLater(tester, meetsGuideline(_OnlyTarget(label)));
  }
}

bool _tappable(SemanticsNode node) {
  final data = node.getSemanticsData();
  return !node.isMergedIntoParent &&
      data.label.isNotEmpty &&
      (data.hasAction(SemanticsAction.tap) ||
          data.hasAction(SemanticsAction.longPress));
}

/// `androidTapTargetGuideline` is typed as the base class, so its two values
/// are not reachable through it; these are the ones it is declared with.
class _OnlyTarget extends MinimumTapTargetGuideline {
  const _OnlyTarget(this.label)
    : super(
        size: const Size(48, 48),
        link:
            'https://support.google.com/accessibility/android/answer/7101858?hl=en',
      );

  final String label;

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      super.shouldSkipNode(node) || node.label != label;
}
