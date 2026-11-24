import 'package:bambuddy_mobile/features/common/chips_or_select.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// Chips while they fit in two rows, a select after: measured from the layout,
/// with only the shown one reachable.
void main() {
  Wrap chips(int n) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 1; i <= n; i++)
        ChoiceChip(
          label: Text('Printer $i'),
          selected: i == 1,
          onSelected: (_) {},
        ),
    ],
  );

  Widget host(int n, {double width = 360, double scale = 1}) => plApp(
    Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: ChipsOrSelect(
            chips: chips(n),
            select: const TextField(key: Key('select')),
          ),
        ),
      ),
    ),
    builder: textScaled(scale),
  );

  final select = find.byKey(const Key('select')).hitTestable();
  final anyChip = find.byType(ChoiceChip).hitTestable();

  Future<void> pump(WidgetTester tester, int n, {double scale = 1}) async {
    await tester.pumpWidget(host(n, scale: scale));
    await tester.pumpAndSettle();
  }

  testWidgets('a few chips stay chips', (tester) async {
    await pump(tester, 3);

    expect(anyChip, findsNWidgets(3));
    expect(select, findsNothing);
  });

  testWidgets('the same labels need the select sooner at a larger text', (
    tester,
  ) async {
    await pump(tester, 6);
    final atNormal = select.evaluate().isNotEmpty;
    await pump(tester, 6, scale: 2);
    final atDouble = select.evaluate().isNotEmpty;

    expect(atNormal, isFalse, reason: 'six chips are two rows at 360 dp');
    expect(atDouble, isTrue, reason: 'at 200% the same six are more than two');
  });

  testWidgets('the select takes the width of the slot', (tester) async {
    await pump(tester, 30);

    expect(tester.getSize(select).width, 360);
  });

  testWidgets('a hidden chip is not read by a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, 30);

    expect(find.bySemanticsLabel(RegExp('Printer 2')), findsNothing);
    handle.dispose();
  });

  group('the keyboard', () {
    Future<List<Widget?>> tabThrough(WidgetTester tester, int times) async {
      final landed = <Widget?>[];
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus?.context;
        landed.add(
          focus?.findAncestorWidgetOfExactType<ChoiceChip>() ??
              focus?.findAncestorWidgetOfExactType<TextField>(),
        );
      }
      return landed;
    }

    testWidgets('never lands on a chip that is hidden', (tester) async {
      await pump(tester, 30);

      final landed = await tabThrough(tester, 40);

      expect(landed.whereType<ChoiceChip>(), isEmpty);
      expect(landed.whereType<TextField>(), isNotEmpty);
    });

    testWidgets('never lands on a select that is hidden', (tester) async {
      await pump(tester, 3);

      final landed = await tabThrough(tester, 10);

      expect(landed.whereType<TextField>(), isEmpty);
      expect(landed.whereType<ChoiceChip>(), isNotEmpty);
    });
  });

  testWidgets('a fleet that grows and shrinks again keeps the focus right', (
    tester,
  ) async {
    Future<Iterable<Widget>> landed() async {
      final found = <Widget>[];
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus?.context;
        final w =
            focus?.findAncestorWidgetOfExactType<ChoiceChip>() ??
            focus?.findAncestorWidgetOfExactType<TextField>();
        if (w != null) found.add(w);
      }
      return found;
    }

    await pump(tester, 30);
    expect((await landed()).whereType<ChoiceChip>(), isEmpty);
    await pump(tester, 3);
    final back = await landed();
    expect(back.whereType<TextField>(), isEmpty);
    expect(back.whereType<ChoiceChip>(), isNotEmpty);
    await pump(tester, 30);
    expect((await landed()).whereType<ChoiceChip>(), isEmpty);
  });

  testWidgets('without a bounded width it says so', (tester) async {
    final reported = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        reported.add(details.exceptionAsString());
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      plApp(
        Scaffold(
          body: Row(
            children: [
              ChipsOrSelect(chips: chips(2), select: const SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(reported.any((r) => r.contains('needs a bounded width')), isTrue);
  });

  test('only a start-aligned horizontal Wrap can be counted', () {
    expect(
      () => ChipsOrSelect(
        chips: const Wrap(crossAxisAlignment: WrapCrossAlignment.center),
        select: const SizedBox(),
      ),
      throwsAssertionError,
    );
    expect(
      () => ChipsOrSelect(
        chips: const Wrap(direction: Axis.vertical),
        select: const SizedBox(),
      ),
      throwsAssertionError,
    );
  });
}
