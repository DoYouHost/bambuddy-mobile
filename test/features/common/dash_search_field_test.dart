import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/interaction_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:bambuddy_mobile/features/common/dash_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  late LogStore store;
  late InteractionProbe probe;

  setUp(() {
    store = LogStore(
      header: LogHeader(
        ts: DateTime.utc(2026, 7, 26, 12),
        session: 'test',
        app: '0.11.2+1102',
        flavor: 'mobile',
      ),
    );
    probe = InteractionProbe(store: store);
  });

  tearDown(() => probe.detach());

  /// Detaching inside the test body is required: the framework verifies that no
  /// SemanticsHandle is alive as soon as the body returns, before tearDown.
  List<Map<String, dynamic>> stop() {
    probe.detach();
    return [
      for (final line in const LineSplitter().convert(store.export()).skip(1))
        jsonDecode(line) as Map<String, dynamic>,
    ];
  }

  testWidgets('names the clear button apart from the field itself',
      (tester) async {
    // Without its own tag the clear button inherits the field's id, and the log
    // cannot tell "searched again" from "gave up and wiped the query" — a live
    // run is what exposed it, since both readings are plausible in code.
    await tester.pumpWidget(
      plApp(
        Scaffold(
          body: DashSearchField(
            id: 'inventory.search',
            hintText: 'Szukaj',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    probe.attach();
    await tester.enterText(find.byType(TextField), 'petg');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(stop().last['id'], 'inventory.search.clear');
  });
}
