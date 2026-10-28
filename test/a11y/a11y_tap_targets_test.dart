import 'package:dash_kit/dash_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// A filterable select whose arrow is boxed by [box] dp (the node it leaves is 8 dp
/// smaller: the menu pads the arrow by 4 dp on every side).
Future<Evaluation> _evaluate(WidgetTester tester, {double? box}) async {
  useLogicalWindow(tester, const Size(411, 800));
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: Builder(
              builder: (context) => dashCombo<int>(
                context,
                id: 'test.combo',
                label: const Text('Printer'),
                filterable: true,
                initialSelection: 1,
                decorationTheme: box == null
                    ? null
                    : InputDecorationTheme(
                        suffixIconConstraints: BoxConstraints.tightFor(
                          width: box,
                          height: box,
                        ),
                      ),
                entries: const [DropdownMenuEntry(value: 1, label: 'One')],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final result = await const A11yTapTargets().evaluate(tester);
  handle.dispose();
  return result;
}

/// A scroll that does not mark itself implicit: Flutter's guideline skips a node
/// at the edge of a scrollable only for one that does, and a page can be built so.
class _NoImplicitScroll extends ClampingScrollPhysics {
  const _NoImplicitScroll({super.parent});

  @override
  bool get allowImplicitScrolling => false;

  @override
  _NoImplicitScroll applyTo(ScrollPhysics? ancestor) =>
      _NoImplicitScroll(parent: buildParent(ancestor));
}

void main() {
  testWidgets('the combo arrow at its shipped size is the one exception', (
    tester,
  ) async {
    expect((await _evaluate(tester)).passed, isTrue);
  });

  testWidgets('a combo arrow under the 40 dp floor is not excused', (
    tester,
  ) async {
    // Box 40 leaves a 32 dp button.
    expect((await _evaluate(tester, box: 40)).passed, isFalse);
  });

  testWidgets('the exception does not reach any other control', (tester) async {
    useLogicalWindow(tester, const Size(411, 800));
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // An `IconButton` would pad its target to 48 on its own.
            child: SizedBox(
              width: 36,
              height: 36,
              child: InkWell(onTap: () {}, child: const Icon(Icons.close)),
            ),
          ),
        ),
      ),
    );
    expect((await const A11yTapTargets().evaluate(tester)).passed, isFalse);
    handle.dispose();
  });

  group('a control the viewport cuts', () {
    /// A 400 dp page with a [size] square button whose top is at [top].
    Widget list({
      required double top,
      required double size,
      double scale = 1,
    }) => MaterialApp(
      home: Scaffold(
        body: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 400,
            child: SingleChildScrollView(
              physics: const _NoImplicitScroll(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: top),
                  // Not flush with the left: Flutter's own skip would take it.
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Semantics(
                      label: 'cut',
                      button: true,
                      child: InkWell(
                        onTap: () {},
                        child: SizedBox(width: size, height: size),
                      ),
                    ),
                  ),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> pumpList(WidgetTester tester, Widget app) async {
      useLogicalWindow(tester, const Size(411, 800));
      await tester.pumpWidget(app);
    }

    testWidgets('is not measured as a small one, scaled or not', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      for (final scale in const [1.0, 1.07]) {
        // 20 dp of a 48 dp button show above the fold.
        await pumpList(tester, list(top: 380, size: 48, scale: scale));
        expect(
          (await const A11yTapTargets().evaluate(tester)).passed,
          isTrue,
          reason: 'scale $scale',
        );
      }
      handle.dispose();
    });

    testWidgets('the stock guideline reads it as small', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester, list(top: 380, size: 48));
      // What the override is for: if Flutter stops doing this, so can we.
      expect(
        (await const MinimumTapTargetGuideline(
          size: Size(48, 48),
          link: '',
        ).evaluate(tester)).passed,
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('a control that is too small and whole still fails', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester, list(top: 100, size: 36));
      expect((await const A11yTapTargets().evaluate(tester)).passed, isFalse);
      handle.dispose();
    });

    testWidgets('a clip that is not a scrollable cuts nothing', (tester) async {
      final handle = tester.ensureSemantics();
      useLogicalWindow(tester, const Size(411, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              // The clip is exactly the button's size: flush, and not a viewport.
              child: ClipRect(
                child: Semantics(
                  label: 'small',
                  button: true,
                  child: InkWell(
                    onTap: () {},
                    child: const SizedBox(width: 36, height: 36),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect((await const A11yTapTargets().evaluate(tester)).passed, isFalse);
      handle.dispose();
    });

    testWidgets('paging with an overlap still measures one on a page seam', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // Its top is 10 dp above the first page's edge: cut at the first stop, and
      // cut at the second if the stops did not overlap.
      await pumpList(tester, list(top: 390, size: 36));
      await expectLater(
        a11yMeetsAllWhileScrolling(tester),
        throwsA(isA<TestFailure>()),
      );
      handle.dispose();
    });
  });
}
