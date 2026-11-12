import 'package:bambuddy_mobile/features/common/dash_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// The empty state inside a screen's own scroll view, the shape archive, files,
/// print log and inventory use: a sliver above it, `SliverEmptyState` below.
void main() {
  Future<void> pumpEmpty(WidgetTester tester, {Size? window}) async {
    if (window != null) useLogicalWindow(tester, window);
    await pumpPhone(
      tester,
      const Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: Text('search bar')),
            SliverEmptyState(message: 'Nothing here', icon: Icons.search_off),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('lays out without an intrinsic-height error', (tester) async {
    await pumpEmpty(tester);

    // A nested viewport throws "RenderViewport does not support returning
    // intrinsic dimensions" while laying out, which surfaces as an exception.
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byIcon(Icons.search_off), findsOneWidget);
  });

  testWidgets('keeps the sliver above it', (tester) async {
    await pumpEmpty(tester);

    expect(find.text('search bar'), findsOneWidget);
  });

  testWidgets('still fits a window shorter than its content', (tester) async {
    // The message block alone is taller than 100 dp: it scrolls with the
    // screen instead of overflowing.
    await pumpEmpty(tester, window: const Size(411, 100));

    expect(tester.takeException(), isNull);
  });
}
