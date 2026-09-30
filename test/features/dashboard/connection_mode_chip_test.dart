import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/connection_mode_chip.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

Widget _chip(WsConnectionState? state) => ProviderScope(
  overrides: [
    wsConnectionStateProvider.overrideWith(
      (ref) => state == null ? const Stream.empty() : Stream.value(state),
    ),
  ],
  child: plApp(const Scaffold(body: ConnectionModeChip())),
);

void main() {
  testWidgets('WS connected → "Live" label', (tester) async {
    await tester.pumpWidget(_chip(WsConnectionState.connected));
    await tester.pump();

    expect(find.text('Na żywo'), findsOneWidget);
    expect(find.text('Odświeżanie'), findsNothing);
    // Live pill uses a green status dot (no sync icon).
    expect(find.byIcon(Icons.sync), findsNothing);
  });

  testWidgets('WS disconnected → "Refreshing" label (polling)', (tester) async {
    await tester.pumpWidget(_chip(WsConnectionState.waitingRetry));
    await tester.pump();

    expect(find.text('Odświeżanie'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('no state data → treated as polling', (tester) async {
    await tester.pumpWidget(_chip(null));
    await tester.pump();

    expect(find.text('Odświeżanie'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('the label sits in the middle of the pill at ${scale}x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPhone(
        tester,
        Scaffold(
          appBar: AppBar(actions: const [Center(child: ConnectionModeChip())]),
        ),
        overrides: [
          wsConnectionStateProvider.overrideWith(
            (_) => Stream.value(WsConnectionState.connected),
          ),
        ],
      );
      await settle(tester);

      final pill = tester.getRect(
        find
            .descendant(
              of: find.byType(ConnectionModeChip),
              matching: find.byType(Container),
            )
            .first,
      );
      final label = tester.getRect(find.byType(Text));
      expect(label.center.dy, closeTo(pill.center.dy, 0.5));
      // A squeezed label keeps a centred box but draws its line from the top,
      // past the box's bottom — so the box has to be as tall as the line.
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(paragraph.textSize.height),
      );
    });
  }
}
