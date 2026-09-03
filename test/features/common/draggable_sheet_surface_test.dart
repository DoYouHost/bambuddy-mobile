import 'package:bambuddy_mobile/features/common/dash_sheet.dart';
import 'package:bambuddy_mobile/features/common/sheet_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The shell every content sheet in the app is built from.
///
/// Both things asserted here used to be re-stated at each of the twelve call
/// sites, which is exactly how one of them gets dropped: a sheet that forgets
/// `expand: false` opens full height whatever size it asked for, and one whose
/// scroll view ignores the controller it was handed drags the whole sheet
/// instead of scrolling.
void main() {
  /// Opens a sheet whose content is a list long enough to scroll, and reports
  /// the controller the shell handed the content.
  Future<ScrollController> openSheet(
    WidgetTester tester, {
    double? initialSize,
  }) async {
    ScrollController? handed;
    await tester.pumpWidget(plApp(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => dashSurfaceSheet<void>(
              context,
              builder: (_) => DraggableSheetSurface(
                initialSize: initialSize ?? 0.7,
                builder: (context, controller) {
                  handed = controller;
                  return ListView(
                    controller: controller,
                    children: [
                      for (var i = 0; i < 60; i++)
                        SizedBox(height: 40, child: Text('row $i')),
                    ],
                  );
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return handed!;
  }

  testWidgets('opens at the size it asked for, not full height', (tester) async {
    await openSheet(tester, initialSize: 0.5);

    final screen = tester.getSize(find.byType(MaterialApp)).height;
    final sheet = tester.getSize(find.byType(SheetSurface)).height;
    expect(sheet / screen, closeTo(0.5, 0.02));
  });

  testWidgets('hands the content a controller its scroll view is driven by',
      (tester) async {
    final controller = await openSheet(tester);

    expect(controller.hasClients, isTrue,
        reason: 'a content scroll view that ignores it drags the sheet instead');

    // The controller sequences the two effects: an upward drag grows the sheet
    // to its maximum first, and only once there does dragging scroll the
    // content. That ordering is the whole point of the content taking this
    // controller rather than one of its own.
    await tester.drag(find.text('row 1'), const Offset(0, -400));
    await tester.pumpAndSettle();
    final screen = tester.getSize(find.byType(MaterialApp)).height;
    expect(tester.getSize(find.byType(SheetSurface)).height / screen,
        closeTo(0.95, 0.02));

    await tester.drag(find.text('row 1'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('draws one surface, so the drag handle is not doubled',
      (tester) async {
    await openSheet(tester);
    expect(find.byType(SheetSurface), findsOneWidget);
  });
}
