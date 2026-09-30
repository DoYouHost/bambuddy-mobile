import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/connection_mode_chip.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
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
