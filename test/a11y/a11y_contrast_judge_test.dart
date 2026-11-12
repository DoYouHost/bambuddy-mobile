import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'a11y_contrast_report.dart';

/// A finding as `MinimumTextContrastGuideline` words it, for the node that
/// carries [text].
String _finding(WidgetTester tester, String text, {double size = 12}) {
  final id = tester.getSemantics(find.text(text)).id;
  return 'SemanticsNode#$id(Rect.fromLTRB(0.0, 0.0, 10.0, 10.0), label: '
      '"$text", textDirection: ltr):\n'
      'Expected contrast ratio of at least 4.5 but found 1.2 for a font size '
      'of $size.';
}

Future<ContrastVerdict> _judge(
  WidgetTester tester, {
  required Color ground,
  required Color ink,
  double size = 12,
  FontWeight? weight,
  double opacity = 1,
  double? devicePixelRatio,
}) async {
  tester.view.physicalSize = const Size(300, 200);
  tester.view.devicePixelRatio = devicePixelRatio ?? 1;
  addTearDown(tester.view.reset);
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(
    MaterialApp(
      home: ColoredBox(
        color: ground,
        child: Center(
          child: Opacity(
            opacity: opacity,
            child: Text(
              'Sample',
              // A real face: the test default paints every glyph as a solid
              // block, which is no text at all for a pixel measure.
              style: TextStyle(
                color: ink,
                fontSize: size,
                fontWeight: weight,
                fontFamily: 'Manrope',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final judged = await judgeContrastFindings(tester, {
    'k': _finding(tester, 'Sample', size: size),
  });
  handle.dispose();
  return judged['k']!.verdict;
}

void main() {
  testWidgets('text that reads by its own colours is an artefact', (
    tester,
  ) async {
    expect(
      await _judge(
        tester,
        ground: const Color(0xFFF6F8F4),
        // textTertiary of the light theme: 67% ink, about 5:1.
        ink: const Color(0xAB202318),
      ),
      ContrastVerdict.artefact,
    );
  });

  testWidgets('text that is too pale by its own colours is genuine', (
    tester,
  ) async {
    expect(
      await _judge(
        tester,
        ground: const Color(0xFFFFFFFF),
        ink: const Color(0xFFAAAAAA),
      ),
      ContrastVerdict.genuine,
    );
  });

  testWidgets('the ancestor opacity counts', (tester) async {
    expect(
      await _judge(
        tester,
        ground: const Color(0xFFFFFFFF),
        ink: const Color(0xFF202318),
        opacity: 0.35,
      ),
      ContrastVerdict.genuine,
    );
  });

  testWidgets('large text is held to 3:1, small to 4.5:1', (tester) async {
    // #767676 on white is 4.54:1; #949494 is 3.03:1.
    expect(
      await _judge(
        tester,
        ground: const Color(0xFFFFFFFF),
        ink: const Color(0xFF949494),
        size: 20,
      ),
      ContrastVerdict.artefact,
    );
    expect(
      await _judge(
        tester,
        ground: const Color(0xFFFFFFFF),
        ink: const Color(0xFF949494),
        size: 12,
      ),
      ContrastVerdict.genuine,
    );
  });

  testWidgets('a finding it cannot place stays a finding', (tester) async {
    tester.view.physicalSize = const Size(300, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: Text('Sample'))),
    );
    final judged = await judgeContrastFindings(tester, {
      'k':
          'SemanticsNode#9999(Rect.fromLTRB(0.0, 0.0, 1.0, 1.0), label: "x"):\n'
          'Expected contrast ratio of at least 4.5 but found 1.2 for a font '
          'size of 12.0.',
    });

    handle.dispose();
    expect(judged['k']!.verdict, ContrastVerdict.inconclusive);
  });

  testWidgets('off a device pixel ratio of 1 nothing is judged', (
    tester,
  ) async {
    expect(
      await _judge(
        tester,
        ground: const Color(0xFFF6F8F4),
        ink: const Color(0xFF202318),
        devicePixelRatio: 2,
      ),
      ContrastVerdict.inconclusive,
    );
  });
}
