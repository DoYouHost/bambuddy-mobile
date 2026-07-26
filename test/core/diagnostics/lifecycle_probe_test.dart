import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/lifecycle_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LogStore store;
  late LifecycleProbe probe;

  setUp(() {
    store = LogStore(
      header: LogHeader(
        ts: DateTime.utc(2026, 7, 26, 12),
        session: 'test',
        app: '0.11.2+1102',
        flavor: 'mobile',
      ),
    );
    probe = LifecycleProbe(store: store);
  });

  List<Map<String, dynamic>> records() => [
        for (final line in const LineSplitter().convert(store.export()).skip(1))
          jsonDecode(line) as Map<String, dynamic>,
      ];

  /// The order Android really sends: leaving is resumed → inactive → hidden →
  /// paused, coming back is the same run backwards.
  Future<void> leaveAndReturn(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  testWidgets('records leaving the app and coming back', (tester) async {
    probe.attach();
    addTearDown(probe.detach);

    await leaveAndReturn(tester);

    // Two records, not six: the states in between are a notification shade or
    // a permission dialog, not the user leaving.
    expect(
      records().map((r) => [r['src'], r['evt'], r['state']]),
      [
        ['app', 'lifecycle', 'paused'],
        ['app', 'lifecycle', 'resumed'],
      ],
    );
  });

  testWidgets('says nothing once the recording is over', (tester) async {
    probe.attach();
    probe.detach();

    await leaveAndReturn(tester);

    expect(records(), isEmpty);
  });
}
