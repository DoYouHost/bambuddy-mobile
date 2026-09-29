import 'dart:convert';
import 'dart:io';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/dash_search_field.dart';
import 'package:bambuddy_mobile/features/common/sliver_search_bar.dart';
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

  testWidgets('names the clear button apart from the field itself', (
    tester,
  ) async {
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

  testWidgets('hint and cursor sit in the middle of the pill', (tester) async {
    // The icon makes the pill 48 dp tall, a line of text is shorter, and a
    // borderless field aligns its text to the top: on a phone the hint sat
    // ~3 dp high in every search bar of the app.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDashThemeData(Brightness.dark, brand: bambuddyBrand),
        home: Scaffold(
          body: DashSearchField(hintText: 'Szukaj', onChanged: (_) {}),
        ),
      ),
    );

    final pill = tester.getRect(find.byType(DecoratedBox).first).center.dy;
    expect(tester.getRect(find.text('Szukaj')).center.dy, pill);
    expect(tester.getRect(find.byType(EditableText)).center.dy, pill);
  });

  for (final scale in [1.3, 2.0]) {
    for (final withButton in [false, true]) {
      testWidgets(
        'at text size $scale the field keeps its text inside the pill '
        '(button beside it: $withButton)',
        (tester) async {
          // The pill grew with the text and overflowed the header reserving
          // 48 dp for it, or — boxed to 48 dp next to a button — squeezed the
          // line and pushed it out through the top.
          await tester.pumpWidget(
            MaterialApp(
              theme: buildDashThemeData(Brightness.dark, brand: bambuddyBrand),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 700),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      DashSliverSearchBar(
                        child: DashSearchField(
                          hintText: 'Szukaj drukarek…',
                          onChanged: (_) {},
                          trailing: [
                            if (withButton)
                              const SizedBox(width: 48, height: 48),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          final pill = tester.getRect(
            find
                .descendant(
                  of: find.byType(DashSearchField),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          final text = tester.getRect(find.byType(EditableText));
          expect(pill.height, DashSearchField.height);
          expect(text.top, greaterThanOrEqualTo(pill.top));
          expect(text.bottom, lessThanOrEqualTo(pill.bottom));
          expect(text.center.dy, pill.center.dy);
        },
      );
    }
  }

  test('no screen builds a search field of its own', () {
    // The AMS slot sheet had one, so the alignment fix above never reached it.
    final handBuilt = RegExp(
      r'prefixIcon:\s*(const\s+)?Icon\(\s*Icons\.search\b',
    );
    final offenders = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .where((f) => !f.path.endsWith('dash_search_field.dart')))
        if (handBuilt.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty, reason: 'use DashSearchField instead');
  });
}
