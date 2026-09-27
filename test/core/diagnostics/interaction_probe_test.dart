import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_tag_material.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What bambuddy encodes in a `Semantics(identifier:)` beyond the id, and what
/// the log does with it.
///
/// The probe's own behaviour — that a decomposer splits an id from its fields
/// at all, that the fields inherit to a deeper node, that a drag drops them —
/// belongs to `app_diagnostics` and is tested there against a fake grammar.
/// This is the other half: the filament vocabulary itself, which is the entire
/// safety argument for carrying any card content in a log.

void main() {
  late LogStore store;
  late InteractionProbe probe;

  setUp(() {
    store = LogStore(
      header: LogHeader(
        ts: DateTime.utc(2026, 7, 25, 12),
        session: 'test',
        app: '0.11.2+1102',
      ),
    );
    // The decomposer is what makes the identifier grammar below mean anything:
    // without it `inventory.spool@PETG` is just a long id.
    probe = InteractionProbe(store: store, decompose: bambuddyIdFields);
  });

  tearDown(() => probe.detach());

  /// Stops recording, then returns every record except the header line.
  /// Detaching inside the test body is required: the framework verifies that
  /// no SemanticsHandle is alive as soon as the body returns, before tearDown.
  List<Map<String, dynamic>> stop() {
    probe.detach();
    return [
      for (final line in const LineSplitter().convert(store.export()).skip(1))
        jsonDecode(line) as Map<String, dynamic>,
    ];
  }

  Future<void> pumpApp(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    probe.attach();
    // Semantics is compiled on the next frame after ensureSemantics.
    await tester.pump();
  }

  testWidgets('records the filament material as a field of its own', (
    tester,
  ) async {
    // Material is the one thing on a card the log carries: it explains a share
    // of AMS reports and identifies nobody. It rides on the identifier because
    // semantics is the only channel the probe has, and comes back out split.
    await pumpApp(
      tester,
      Center(
        child: logTagMaterial(
          'inventory.spool',
          'PETG',
          ElevatedButton(onPressed: () {}, child: const Text('Szpula')),
        ),
      ),
    );

    await tester.tap(find.text('Szpula'));
    await tester.pump();

    final record = stop().single;
    expect(record['id'], 'inventory.spool');
    expect(record['mat'], 'PETG');
  });

  testWidgets('drops a material outside the known list', (tester) async {
    // A spool's material is text the user typed into the form, so an
    // unrecognised value must leave no trace at all — not the id, not a field.
    await pumpApp(
      tester,
      Center(
        child: logTagMaterial(
          'inventory.spool',
          'Rain Gauge PLA',
          ElevatedButton(onPressed: () {}, child: const Text('Szpula')),
        ),
      ),
    );

    await tester.tap(find.text('Szpula'));
    await tester.pump();

    final record = stop().single;
    expect(record['id'], 'inventory.spool');
    expect(record.containsKey('mat'), isFalse);
  });

  testWidgets('the material reaches a control inside the tagged card', (
    tester,
  ) async {
    // Same inheritance as the identifier: a tap on something deeper inside the
    // spool tile still knows what was in it.
    await pumpApp(
      tester,
      Center(
        child: logTagMaterial(
          'inventory.spool',
          'TPU',
          Material(
            child: InkWell(
              onTap: () {},
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    final record = stop().single;
    expect(record['id'], 'inventory.spool');
    expect(record['mat'], 'TPU');
  });

  testWidgets('a drag does not claim the material it started on', (
    tester,
  ) async {
    // Scrolling the spool list named `inventory.spool` *and* its material in a
    // live run. One drag record stands for a folded burst of flicks over
    // different rows, so the field would speak for rows it never touched — and
    // a scroll is no decision about a filament anyway.
    await pumpApp(
      tester,
      ListView(
        children: [
          for (var i = 0; i < 40; i++)
            logTagMaterial(
              'inventory.spool',
              'PETG',
              Material(
                child: InkWell(onTap: () {}, child: Text('Szpula $i')),
              ),
            ),
        ],
      ),
    );

    await tester.fling(find.text('Szpula 1'), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();

    final drag = stop().firstWhere((r) => r['evt'] == 'drag');
    expect(drag['id'], 'inventory.spool');
    expect(drag.containsKey('mat'), isFalse);
  });
}
