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
}
