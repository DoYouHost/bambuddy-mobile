import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/controller/controller_detail_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// Where [finder] is drawn, through every transform above it.
Rect _onScreen(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder.first);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Widget _dialog() => plApp(
  Scaffold(
    body: ControllerDetailDialog(
      scale: 1.07,
      closeId: 'test.close',
      thumbnail: const SizedBox(width: 148, height: 148),
      title: 'a_rather_long_file_name_for_a_dialog.gcode.3mf',
      facts: const [
        ControllerFact(Icons.sd_card_outlined, '4.1 MB'),
        ControllerFact(Icons.print_outlined, 'P1S Warsztat'),
        ControllerFact(Icons.schedule, '1h 30min'),
        ControllerFact(Icons.scale_outlined, '96 g'),
        ControllerFact(Icons.event, '10/20/2026 10:39 PM'),
      ],
      reason: 'Pocięty dla H2D; ta drukarka to P1S.',
      actions: [
        ControllerDialogAction(
          id: 'test.delete',
          icon: Icons.delete_outline,
          label: 'Usuń',
          onPressed: () {},
        ),
        ControllerDialogAction(
          id: 'test.print',
          icon: Icons.print_outlined,
          label: 'Drukuj',
          onPressed: () {},
        ),
        ControllerDialogAction(
          id: 'test.queue',
          icon: Icons.playlist_add,
          label: 'Do kolejki',
          onPressed: () {},
        ),
      ],
    ),
  ),
);

void main() {
  for (final textScale in const [1.0, 1.15, 1.29, 1.5, 2.0]) {
    testWidgets('the detail dialog keeps its touch targets 48 dp at '
        '${(textScale * 100).round()} % text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      useLogicalWindow(tester, landscapeRedmi);
      await tester.pumpWidget(_dialog());

      expect(tester.takeException(), isNull);
      for (final id in [
        'test.close',
        'test.delete',
        'test.print',
        'test.queue',
      ]) {
        final r = _onScreen(tester, byLogId(id));
        expect(r.height, greaterThanOrEqualTo(47.9), reason: id);
        expect(r.left, greaterThanOrEqualTo(0), reason: id);
        expect(r.right, lessThanOrEqualTo(landscapeRedmi.width), reason: id);
        expect(r.bottom, lessThanOrEqualTo(landscapeRedmi.height), reason: id);
      }
    });
  }

  // The actions are one row of equal shares or, where a label does not fit its
  // share, one under the other across the whole width: either way they span the
  // dialog's content, never a few buttons standing at the left edge.
  for (final window in const [Size(891, 411), Size(520, 400)]) {
    for (final textScale in const [1.5, 2.0]) {
      testWidgets('the actions fill the dialog at ${(textScale * 100).round()} % '
          'text in a ${window.width.round()} dp window', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        useLogicalWindow(tester, window);
        await tester.pumpWidget(_dialog());

        // The dialog's own surface: the `Dialog` widget's box includes its inset.
        final dialog = _onScreen(
          tester,
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(Material),
          ),
        );
        final inner = dialog.deflate(DashSpace.md);
        final rects = [
          for (final id in ['test.delete', 'test.print', 'test.queue'])
            _onScreen(tester, byLogId(id)),
        ];
        final left = rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
        final right = rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
        expect(left, closeTo(inner.left, 1));
        expect(right, closeTo(inner.right, 1));
      });
    }
  }

  testWidgets('a fact pill scales its icon once', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    useLogicalWindow(tester, landscapeRedmi);
    await tester.pumpWidget(_dialog());

    // 16 dp at the icon's own rule: 1.5 times at most, not 2 times that again.
    expect(
      _onScreen(tester, find.byIcon(Icons.sd_card_outlined)).width,
      lessThanOrEqualTo(24.5),
    );
  });

  testWidgets('a long dialog scrolls and keeps its actions on the screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    useLogicalWindow(tester, const Size(640, 300));
    await tester.pumpWidget(_dialog());

    expect(tester.takeException(), isNull);
    expect(
      _onScreen(tester, byLogId('test.print')).bottom,
      lessThanOrEqualTo(300),
    );
  });
}
