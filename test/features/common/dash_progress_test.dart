import 'package:bambuddy_mobile/features/common/dash_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the page spinner centres itself in what it was given', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 300, height: 200, child: DashLoading())),
      ),
    );

    final box = tester.getRect(find.byType(SizedBox).first);
    final spinner = tester.getRect(find.byType(CircularProgressIndicator));
    expect(spinner.center.dx, box.center.dx);
    expect(spinner.center.dy, box.center.dy);
  });

  testWidgets('the inline spinner keeps the slot it was given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: DashSpinner(size: 16)))),
    );

    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(16, 16),
    );
  });

  testWidgets('it defaults to the size most rows ask for, and takes a colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: DashSpinner(color: Color(0xFF00FF00)))),
      ),
    );

    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(18, 18),
    );
    final indicator =
        tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(indicator.color, const Color(0xFF00FF00));
    // Thin at every size, or it reads as an icon rather than as waiting.
    expect(indicator.strokeWidth, 2);
  });
}
