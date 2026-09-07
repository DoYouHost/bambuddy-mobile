import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/interaction_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LogStore store;
  late InteractionProbe probe;

  setUp(() {
    store = LogStore(
      header: LogHeader(
        ts: DateTime.utc(2026, 7, 25, 12),
        session: 'test',
        app: '0.11.2+1102',
        flavor: 'mobile',
      ),
    );
    probe = InteractionProbe(store: store);
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

  testWidgets('records a tap with the role of what was pressed', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Center(
        child: ElevatedButton(onPressed: () {}, child: const Text('Wyślij')),
      ),
    );

    await tester.tap(find.text('Wyślij'));
    await tester.pump();

    final recorded = stop();
    expect(recorded, hasLength(1));
    final record = recorded.single;
    expect(record['src'], 'ui');
    expect(record['evt'], 'tap');
    expect(record['role'], 'button');
  });

  testWidgets('stamps a touch with the moment the finger went down', (
    tester,
  ) async {
    // The widget's handler runs before the pointer-up event reaches this probe,
    // so a record stamped at write time lands *after* whatever the tap set off.
    // With HTTP, WebSocket and the background service on the same timeline,
    // reading effects before their cause costs real time.
    final origin = DateTime.utc(2026, 7, 25, 12);
    var now = origin;
    store = LogStore(
      header: LogHeader(
        ts: origin,
        session: 'test',
        app: '0.11.2+1102',
        flavor: 'mobile',
      ),
      clock: () => now,
    );
    probe = InteractionProbe(store: store);

    await pumpApp(
      tester,
      Center(
        child: ElevatedButton(
          onPressed: () =>
              store.add(LogSource.ui, 'route', fields: const {'to': '/queue'}),
          child: const Text('Kolejka'),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Kolejka')),
    );
    now = origin.add(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump();

    final recorded = stop();
    expect(recorded.map((r) => r['evt']), ['tap', 'route']);
    expect(recorded.map((r) => r['t']), [0, 120]);
  });

  testWidgets('names a menu item tagged through its child', (tester) async {
    // A `PopupMenuItem` cannot be wrapped: `Semantics` is not a
    // `PopupMenuEntry`. So the tag goes on the item's child, which puts the
    // identifier *below* the node that carries the tap — the opposite of every
    // other tagged control.
    await pumpApp(
      tester,
      Center(
        child: PopupMenuButton<int>(
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 1,
              child: logTag('stats.range.month', const Text('Miesiąc')),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miesiąc'));
    await tester.pumpAndSettle();

    expect(stop().last['id'], 'stats.range.month');
  });

  testWidgets('names a dropdown option through its own popup route', (
    tester,
  ) async {
    // A `DropdownButtonFormField` shows its options in a route of its own, so
    // the field's identifier does not reach them — picking an AMS slot recorded
    // as a bare `menuItem`. The tag has to go on each option, and this pins
    // that it survives the trip through the popup.
    await pumpApp(
      tester,
      Center(
        child: DropdownButtonFormField<int>(
          initialValue: 0,
          items: [
            for (var slot = 0; slot < 4; slot++)
              DropdownMenuItem(
                value: slot,
                child: logTag('spool_assign.slot.$slot', Text('${slot + 1}')),
              ),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();

    expect(stop().last['id'], 'spool_assign.slot.2');
  });

  testWidgets('names a dropdown option tagged below the node that is tapped', (
    tester,
  ) async {
    // `DropdownButtonFormField` is the harder cousin of `PopupMenuItem`: the
    // option's tap sits on a node *above* the tag, and there is no
    // `MergeSemantics` to pull the identifier up into it. A live run recorded
    // picking an AMS slot as a bare `menuItem` because of it.
    await pumpApp(
      tester,
      Center(
        child: DropdownButtonFormField<int>(
          initialValue: 0,
          items: [
            for (var slot = 0; slot < 4; slot++)
              DropdownMenuItem(
                value: slot,
                child: logTag('spool_assign.slot.$slot', Text('${slot + 1}')),
              ),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();

    final record = stop().last;
    expect(record['id'], 'spool_assign.slot.2');
    expect(record['role'], 'menuItem');
  });

  testWidgets('names a dropdown option tapped beside its label', (
    tester,
  ) async {
    // The trap the previous test walks straight past: a tag has the geometry of
    // what it wraps, and an AMS slot label is 24 pixels tall inside a 48-pixel
    // row. Tapping dead centre finds it; a live run tapping the row normally
    // missed it three times out of three. Naming a menu row therefore does not
    // depend on where inside it the finger landed.
    await pumpApp(
      tester,
      Center(
        child: DropdownButtonFormField<int>(
          initialValue: 0,
          items: [
            for (var slot = 0; slot < 4; slot++)
              DropdownMenuItem(
                value: slot,
                child: logTag('spool_assign.slot.$slot', Text('${slot + 1}')),
              ),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();

    // Below the digit but still inside the option's row — the half of it the
    // tag does not cover.
    final label = tester.getRect(find.text('3').last);
    await tester.tapAt(Offset(label.center.dx, label.bottom + 6));
    await tester.pumpAndSettle();

    expect(stop().last['id'], 'spool_assign.slot.2');
  });

  testWidgets('never records the accessibility label', (tester) async {
    // The label of a merged node is the whole content of a card — model names,
    // file names, spool names. The log ends up in a public issue, and no
    // redactor can catch values that dynamic, so labels stay out of it.
    await pumpApp(
      tester,
      Center(
        child: ElevatedButton(
          onPressed: () {},
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text('Nazwa modelu użytkownika'), Text('PLA · 145 g')],
          ),
        ),
      ),
    );

    await tester.tap(find.text('PLA · 145 g'));
    await tester.pump();

    final raw = store.export();
    expect(raw, isNot(contains('Nazwa modelu')));
    expect(raw, isNot(contains('145 g')));
    expect(stop().single.containsKey('label'), isFalse);
  });

  testWidgets('names a control by its declared identifier', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: Semantics(
          identifier: 'controls.home',
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('Pozycja bazowa'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pozycja bazowa'));
    await tester.pump();

    expect(stop().single['id'], 'controls.home');
  });

  testWidgets('reports the button, not the Text inside it', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: ElevatedButton(
          onPressed: () {},
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(Icons.home), Text('Home')],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Home'));
    await tester.pump();

    expect(stop().single['role'], 'button');
  });

  testWidgets('logTag is what screens use to declare an identifier', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Center(
        child: logTag(
          'archive.card',
          ElevatedButton(onPressed: () {}, child: const Text('Model')),
        ),
      ),
    );

    await tester.tap(find.text('Model'));
    await tester.pump();

    expect(stop().single['id'], 'archive.card');
  });

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

  testWidgets('ignores the recorder\'s own controls', (tester) async {
    // Operating the recording bar is not using the app. The recorder writes
    // its own records for what matters (`user_marker`, `recording_stopped`).
    await pumpApp(
      tester,
      Center(
        child: logTag(
          'bug_report.mark',
          ElevatedButton(onPressed: () {}, child: const Text('Oznacz')),
        ),
      ),
    );

    await tester.tap(find.text('Oznacz'));
    await tester.pump();
    await tester.drag(find.text('Oznacz'), const Offset(120, 0));
    await tester.pump();

    expect(stop(), isEmpty);
  });

  testWidgets('reports the control, not the decoration inside it', (
    tester,
  ) async {
    // A card's fill-level bar is the deepest node under the finger, and it made
    // taps on the card read as `role: progressBar`.
    await pumpApp(
      tester,
      Center(
        child: logTag(
          'inventory.spool',
          InkWell(
            onTap: () {},
            child: const SizedBox(
              width: 200,
              height: 80,
              child: Center(child: LinearProgressIndicator(value: 0.4)),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(LinearProgressIndicator)));
    await tester.pump();

    final record = stop().single;
    expect(record['id'], 'inventory.spool');
    expect(record['role'], 'button');
  });

  testWidgets('reports the control under decoration that covers it', (
    tester,
  ) async {
    // The real spool tile: the fill-level bar is a sibling painted over the
    // card's ink well, not a child of it, so it was reported instead of the tap
    // target.
    await pumpApp(
      tester,
      Center(
        child: logTag(
          'inventory.spool',
          SizedBox(
            width: 200,
            height: 80,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InkWell(onTap: () {}, child: const SizedBox()),
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(value: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(LinearProgressIndicator)));
    await tester.pump();

    final record = stop().single;
    expect(record['id'], 'inventory.spool');
    expect(record['role'], 'button');
  });

  testWidgets('climbs out of inert decoration to the control above it', (
    tester,
  ) async {
    // Same defect from the other direction: whatever the semantics tree looks
    // like, an inert node under the finger hands the press to the nearest
    // control above it — but never as far as the list it scrolls in.
    await pumpApp(
      tester,
      ListView(
        children: [
          logTag(
            'inventory.spool',
            InkWell(
              onTap: () {},
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(value: 0.4),
              ),
            ),
          ),
        ],
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(LinearProgressIndicator)));
    await tester.pump();

    final record = stop().single;
    expect(record['id'], 'inventory.spool');
    expect(record['role'], 'button');
  });

  testWidgets('names a tap that dismissed a sheet', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 200),
            ),
            child: const Text('Otwórz'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Otwórz'));
    await tester.pumpAndSettle();
    // Outside the sheet: the modal barrier, whose only action is dismissal.
    await tester.tapAt(const Offset(200, 60));
    await tester.pump();

    expect(stop().last['role'], 'dismiss');
  });

  testWidgets('says when a tap landed on an open route and nothing else', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: const SizedBox.expand(),
      ),
    );

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();

    expect(stop().single['role'], 'route');
  });

  testWidgets('records a tap that hit nothing interactive', (tester) async {
    await pumpApp(tester, const SizedBox.expand());

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();

    final record = stop().single;
    expect(record['evt'], 'tap');
    expect(record.containsKey('label'), isFalse);
    expect(record.containsKey('id'), isFalse);
    expect(record['empty'], isTrue);
  });

  testWidgets('says outright that a tap landed on empty space', (tester) async {
    // A live run showed `{"evt":"tap","id":"dashboard.printer_card"}` — the
    // finger hit the card's body between its controls. Without a word for it,
    // that reads the same as the probe failing to name what was pressed.
    await pumpApp(
      tester,
      logTag(
        'dashboard.printer_card',
        Card(
          child: Column(
            children: [
              const SizedBox(height: 80, child: Text('Drukuje 42%')),
              TextButton(onPressed: () {}, child: const Text('Szczegóły')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Drukuje 42%'));
    await tester.pump();
    await tester.tap(find.text('Szczegóły'));
    await tester.pump();

    final recorded = stop();
    expect(recorded.first['id'], 'dashboard.printer_card');
    expect(recorded.first['empty'], isTrue);
    // The button in the same card is a hit, and stays unmarked.
    expect(recorded.last['role'], 'button');
    expect(recorded.last.containsKey('empty'), isFalse);
  });

  testWidgets('captures the checkbox state before the tap', (tester) async {
    var checked = false;
    await pumpApp(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Center(
          child: Checkbox(
            value: checked,
            onChanged: (v) => setState(() => checked = v ?? false),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(stop().single['was_checked'], isFalse);
    expect(checked, isTrue);
  });

  testWidgets('never logs what was typed into a text field', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: TextField(
          controller: TextEditingController(text: 'sekretna-nazwa-drukarki'),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(stop().single['role'], 'textField');
    expect(store.export(), isNot(contains('sekretna-nazwa-drukarki')));
  });

  testWidgets('a held touch is a long press', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: GestureDetector(
          onLongPress: () {},
          child: const Text('Kafelek'),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Kafelek')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up(timeStamp: const Duration(milliseconds: 700));
    await tester.pump();

    final record = stop().single;
    expect(record['evt'], 'long_press');
    expect(record['held_ms'], 700);
  });

  testWidgets('a moved touch is a drag with a direction', (tester) async {
    await pumpApp(
      tester,
      ListView(children: [for (var i = 0; i < 40; i++) Text('Pozycja $i')]),
    );

    await tester.fling(find.text('Pozycja 1'), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();

    final drag = stop().firstWhere((r) => r['evt'] == 'drag');
    expect(drag['dir'], 'up');
    expect(drag['dist'], greaterThan(24));
  });

  testWidgets('a drag says nothing about hitting empty space', (tester) async {
    // The same dashboard flick came back once as `empty` and once as a
    // `button`, depending on which part of the card the finger started on —
    // while both scrolled. Whether the starting point was operable is a fact
    // about a press, not about a drag.
    await pumpApp(
      tester,
      ListView(
        children: [
          for (var i = 0; i < 20; i++)
            logTag(
              'dashboard.printer_card',
              SizedBox(height: 80, child: Text('Drukarka $i')),
            ),
        ],
      ),
    );

    await tester.fling(find.text('Drukarka 1'), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();

    final drag = stop().firstWhere((r) => r['evt'] == 'drag');
    expect(drag['id'], 'dashboard.printer_card');
    expect(drag.containsKey('empty'), isFalse);
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

  testWidgets('folds a burst of drags on the same target', (tester) async {
    await pumpApp(
      tester,
      ListView(children: [for (var i = 0; i < 60; i++) Text('Pozycja $i')]),
    );

    for (var i = 0; i < 5; i++) {
      final gesture = await tester.createGesture();
      // Inside the quiet period, so everything after the first folds.
      await gesture.down(
        const Offset(200, 300),
        timeStamp: Duration(milliseconds: 100 * i),
      );
      await gesture.moveTo(
        const Offset(200, 100),
        timeStamp: Duration(milliseconds: 100 * i + 50),
      );
      await gesture.up(timeStamp: Duration(milliseconds: 100 * i + 50));
      await tester.pump();
    }

    final drags = stop().where((r) => r['evt'] == 'drag').toList();
    expect(drags, hasLength(1), reason: 'a scroll burst is one record');
    expect(store.recordCount, lessThan(5));
  });

  testWidgets('records nothing once detached', (tester) async {
    await pumpApp(
      tester,
      Center(
        child: ElevatedButton(onPressed: () {}, child: const Text('X')),
      ),
    );

    probe.detach();
    await tester.tap(find.text('X'));
    await tester.pump();

    expect(stop(), isEmpty);
  });

  testWidgets('a row merged for the screen reader still names its control', (
    tester,
  ) async {
    // `MergeSemantics` is how a setting's title is spoken together with the
    // switch that changes it — otherwise a reader announces "off, switch" and
    // six of them look alike. It also collapses the subtree into one node, so
    // the identifier the log resolves against has to survive the collapse; the
    // probe stops at a merged node instead of descending into it.
    await pumpApp(
      tester,
      Center(
        child: MergeSemantics(
          child: Row(
            children: [
              const Expanded(child: Text('Poklatkowy')),
              logTag(
                'queue_edit.timelapse',
                Switch(value: false, onChanged: (_) {}),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(stop().last['id'], 'queue_edit.timelapse');
  });

  testWidgets('a chip that announces it is selected still names itself', (
    tester,
  ) async {
    // `logTag(selected:)` puts the state on the tagged node rather than on a
    // wrapper of its own, because a wrapper annotates a different node — the
    // reader was told nothing and the id would have moved. Both have to be on
    // the one node the press lands on.
    await pumpApp(
      tester,
      Center(
        child: logTag(
          'drying.start_mode.now',
          selected: true,
          InkWell(onTap: () {}, child: const Text('Teraz')),
        ),
      ),
    );

    await tester.tap(find.text('Teraz'));
    await tester.pump();

    expect(stop().last['id'], 'drying.start_mode.now');
  });

  testWidgets('attach twice, detach twice — no leaked handle', (tester) async {
    await pumpApp(tester, const SizedBox.expand());

    probe.attach();
    expect(probe.isAttached, isTrue);
    probe
      ..detach()
      ..detach();

    expect(probe.isAttached, isFalse);
  });
}
