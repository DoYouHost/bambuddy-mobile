import 'package:bambuddy_mobile/features/common/sheet_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const navBar = 48.0;
  final contentKey = UniqueKey();

  testWidgets('a surface sheet reserves the same strip itself', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: navBar),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SheetSurface(child: SizedBox(key: contentKey)),
        ),
      ),
    );

    final surfaceBottom = tester.getRect(find.byType(SheetSurface)).bottom;
    final contentBottom = tester.getRect(find.byKey(contentKey)).bottom;
    expect(surfaceBottom - contentBottom, navBar);
  });

  testWidgets('an open keyboard already covers that strip', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: navBar),
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SheetSurface(child: SizedBox(key: contentKey)),
        ),
      ),
    );

    final surfaceBottom = tester.getRect(find.byType(SheetSurface)).bottom;
    final contentBottom = tester.getRect(find.byKey(contentKey)).bottom;
    expect(surfaceBottom - contentBottom, 0);
  });
}
