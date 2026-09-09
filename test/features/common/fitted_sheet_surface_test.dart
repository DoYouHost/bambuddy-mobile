import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/sheet_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The surface a content-height sheet stands on. It was written out five times
/// before this widget existed, which is exactly how the drag handle ended up
/// with three spellings of the same alpha.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildDashThemeData(Brightness.dark),
      home: Scaffold(body: FittedSheetSurface(child: child)),
    ),
  );

  testWidgets('takes its height from the content, not from the screen', (
    tester,
  ) async {
    // The whole reason it is not `SheetSurface`: that one can be dragged to
    // full height, this one ends where its content does.
    await pump(tester, const SizedBox(height: 120, width: double.infinity));

    final surface = tester.getSize(find.byType(FittedSheetSurface));
    // 10 + 4 handle + 120 content.
    expect(surface.height, lessThan(200));
    expect(surface.height, greaterThan(120));
  });

  testWidgets('draws the drag handle above the content', (tester) async {
    await pump(tester, const Text('treść'));

    final handle = tester.getRect(
      find
          .byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxWidth == 40,
          )
          .first,
    );
    expect(handle.height, 4);
    // Above, not beside: the content starts where the handle ends.
    expect(
      handle.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('treść')).top),
    );
  });

  testWidgets('keeps the content clear of the system navigation bar', (
    tester,
  ) async {
    // Sheets are drawn edge to edge since Android 15, so without this the last
    // row sits under the gesture pill.
    const inset = 48.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDashThemeData(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: inset),
            viewPadding: EdgeInsets.only(bottom: inset),
          ),
          child: const Scaffold(
            body: FittedSheetSurface(child: Text('ostatni wiersz')),
          ),
        ),
      ),
    );

    final surface = tester.getRect(find.byType(FittedSheetSurface));
    final text = tester.getRect(find.text('ostatni wiersz'));
    expect(surface.bottom - text.bottom, greaterThanOrEqualTo(inset));
  });
}
