import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_confirm_dialog.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_scaling_list.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  // Holder because the dialog result only lands after the dialog pops,
  // long after the pump helper has returned.
  bool? result;

  /// Opens the dialog on a real watch face — the small one by default, since a
  /// confirmation is the screen with the least room to spare.
  Future<void> pumpAndOpen(
    WidgetTester tester, {
    Size face = wearFaceSmall,
    WearShape shape = WearShape.round,
    String title = 'Stop print?',
  }) async {
    result = null;
    useWatchFace(tester, shape, face);
    await tester.pumpWidget(
      plApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => WearConfirmDialog(
                  icon: Icons.stop_rounded,
                  title: title,
                  subtitle: 'X1C',
                  confirmColor: const Color(0xFFB3261E),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
        // The dialog is a route, so the shape has to come from above the
        // navigator — see [wearShapeBuilder].
        builder: wearShapeBuilder,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows title, subtitle and both round buttons', (tester) async {
    await pumpAndOpen(tester);
    expect(find.text('Stop print?'), findsOneWidget);
    expect(find.text('X1C'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('confirm pops true', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancel pops false', (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('a long question still leaves the answer reachable', (
    tester,
  ) async {
    // The dialog scrolls, as Wear OS's does, so a question that fills the face
    // pushes the buttons down rather than off it.
    await pumpAndOpen(
      tester,
      title: 'Change the server this watch talks to, dropping every secret?',
    );

    await tapOnWatch(tester, find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('the message is not cut to one line', (tester) async {
    await pumpAndOpen(tester);

    // `TextConfigurationDefaults.MaxLines`: a dialog's text has no limit.
    expect(tester.widget<Text>(find.text('X1C')).maxLines, isNull);
    // `AlertTitleMaxLines`.
    expect(tester.widget<Text>(find.text('Stop print?')).maxLines, 3);
  });

  Size buttonOf(WidgetTester tester, IconData icon) => tester.getSize(
    find.ancestor(of: find.byIcon(icon), matching: find.byType(Material)).first,
  );

  for (final face in [wearFaceSmall, wearFaceLarge]) {
    testWidgets("on $face the buttons are Wear Material 3's", (tester) async {
      await pumpAndOpen(tester, face: face);

      // AlertDialogDefaults.DismissButton, ConfirmButton.
      expect(buttonOf(tester, Icons.close_rounded), const Size.square(60));
      expect(buttonOf(tester, Icons.check_rounded), const Size(63, 54));
    });
  }

  testWidgets('a square face gets no scaling list', (tester) async {
    // The dialog is a route, so this passes only while the shape is injected
    // above the navigator: wrapped around `home` instead, the scope is a
    // sibling of the dialog and it falls back to round — which reads as a
    // perfectly plausible pass here.
    await pumpAndOpen(tester, shape: WearShape.square);
    expect(find.byType(WearScalingSliverList), findsNothing);
  });

  testWidgets('a round face gets the scaling list', (tester) async {
    await pumpAndOpen(tester);
    expect(find.byType(WearScalingSliverList), findsOneWidget);
  });
}
