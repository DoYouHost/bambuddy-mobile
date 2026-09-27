import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

SlicerPipeline _pipeline({required int id, required String name}) =>
    SlicerPipeline(
      id: id,
      name: name,
      printerPreset: const PresetRef(source: 'local', id: '3'),
      processPreset: const PresetRef(source: 'local', id: '9'),
      filamentPresets: const [PresetRef(source: 'local', id: '11')],
    );

final _pipelines = [
  _pipeline(id: 1, name: 'Gridfinity PETG'),
  _pipeline(id: 2, name: 'Draft PLA'),
];

/// Opens the sheet from a button, the way both callers do, and hands back what
/// it popped.
Future<void> _pumpOpened(
  WidgetTester tester, {
  required void Function(SlicerPipeline?) onPicked,
  String Function(SlicerPipeline p)? subtitle,
  Color? Function(ThemeData theme, SlicerPipeline p)? subtitleColor,
}) async {
  await pumpPhone(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => onPicked(
              await pickPipeline(
                context,
                pipelines: _pipelines,
                tag: 'test.option',
                subtitle: (l10n, p) => subtitle?.call(p) ?? 'sub ${p.id}',
                subtitleColor: subtitleColor,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

void main() {
  testWidgets('the list is introduced by a heading', (tester) async {
    // The run screen carried a `Semantics` header and the slice bar did not, so
    // on one of the two a screen reader opened straight into an unnamed list.
    // Sharing the sheet is what makes that impossible to drift apart again.
    await _pumpOpened(tester, onPicked: (_) {});
    final handle = tester.ensureSemantics();

    expect(
      tester
          .getSemantics(find.text('Pipeline'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );

    handle.dispose();
  });

  testWidgets('every pipeline is offered with its own subtitle', (
    tester,
  ) async {
    // The subtitle is the only thing the two callers disagree on — the run
    // screen names the target, the slice bar the presets — so it is the one
    // thing the sheet takes from them.
    await _pumpOpened(
      tester,
      onPicked: (_) {},
      subtitle: (p) => 'summary of ${p.name}',
    );

    expect(find.text('Gridfinity PETG'), findsOneWidget);
    expect(find.text('summary of Gridfinity PETG'), findsOneWidget);
    expect(find.text('summary of Draft PLA'), findsOneWidget);
  });

  testWidgets('a subtitle can be tinted per row', (tester) async {
    // How the run screen marks a pipeline with no target: it stays selectable,
    // because picking it is how the operator finds out it needs an edit.
    await _pumpOpened(
      tester,
      onPicked: (_) {},
      subtitleColor: (theme, p) => p.id == 1 ? const Color(0xFFFF0000) : null,
    );

    expect(
      tester.widget<Text>(find.text('sub 1')).style?.color,
      const Color(0xFFFF0000),
    );
    // A null from the callback leaves `bodySmall` as it was rather than
    // blanking the colour — `copyWith` ignores a null, which is the whole
    // reason the plain rows still read correctly.
    final theme = Theme.of(tester.element(find.text('sub 2')));
    expect(
      tester.widget<Text>(find.text('sub 2')).style?.color,
      theme.textTheme.bodySmall?.color,
    );
  });

  testWidgets('tapping a row answers with that pipeline', (tester) async {
    SlicerPipeline? picked;
    await _pumpOpened(tester, onPicked: (p) => picked = p);

    await tester.tap(find.text('Draft PLA'));
    await settle(tester);

    expect(picked?.id, 2);
  });

  testWidgets('dismissing the sheet answers with nothing', (tester) async {
    // The callers read a null as "the operator changed their mind" and leave
    // the current selection alone, so it has to stay distinguishable.
    var called = false;
    SlicerPipeline? picked;
    await _pumpOpened(
      tester,
      onPicked: (p) {
        called = true;
        picked = p;
      },
    );

    await tester.tapAt(const Offset(200, 20));
    await settle(tester);

    expect(called, isTrue);
    expect(picked, isNull);
  });
}
