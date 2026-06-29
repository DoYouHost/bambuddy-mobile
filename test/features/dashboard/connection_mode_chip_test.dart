import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/connection_mode_chip.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

Widget _chip(WsConnectionState? state) => ProviderScope(
      overrides: [
        wsConnectionStateProvider.overrideWith(
          (ref) =>
              state == null ? const Stream.empty() : Stream.value(state),
        ),
      ],
      child: plApp(const Scaffold(body: ConnectionModeChip())),
    );

void main() {
  testWidgets('WS connected → etykieta „Na żywo"', (tester) async {
    await tester.pumpWidget(_chip(WsConnectionState.connected));
    await tester.pump();

    expect(find.text('Na żywo'), findsOneWidget);
    expect(find.text('Odświeżanie'), findsNothing);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('WS rozłączony → etykieta „Odświeżanie" (polling)',
      (tester) async {
    await tester.pumpWidget(_chip(WsConnectionState.waitingRetry));
    await tester.pump();

    expect(find.text('Odświeżanie'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('brak danych stanu → traktowany jako polling', (tester) async {
    await tester.pumpWidget(_chip(null));
    await tester.pump();

    expect(find.text('Odświeżanie'), findsOneWidget);
  });
}
