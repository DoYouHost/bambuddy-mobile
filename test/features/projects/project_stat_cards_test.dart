import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/features/projects/project_detail_screen.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// Every tile the card can show: the optional wear cost is on, seven in all.
const _stats = ProjectStats(
  totalArchives: 12,
  totalPrintTimeHours: 48.5,
  totalFilamentGrams: 1250,
  estimatedCost: 36.8,
  totalEnergyKwh: 7.25,
  totalWearCost: 1.5,
  bomTotalItems: 9,
  bomCompletedItems: 4,
);

const _icons = [
  Icons.view_in_ar_outlined,
  Icons.schedule_outlined,
  Icons.line_weight_outlined,
  Icons.attach_money_outlined,
  Icons.bolt_outlined,
  Icons.build_outlined,
  Icons.checklist_outlined,
];

void main() {
  // Phone width, text scale, columns the grid must pick. A fixed aspect ratio of
  // 2.6 overflowed by 3 dp at 320 dp, by 5 dp at 150 % and by 24-70 dp at 200 %,
  // and cut the longest labels to an ellipsis.
  for (final (width, scale, columns) in [
    (411.0, 1.0, 2),
    (411.0, 1.5, 1),
    (411.0, 2.0, 1),
    (320.0, 1.0, 1),
    (320.0, 1.5, 1),
    (320.0, 2.0, 1),
  ]) {
    testWidgets(
      'stat tiles at $width dp and text $scale: $columns column(s), nothing '
      'overflows or is cut',
      (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          plApp(
            const Scaffold(
              body: SingleChildScrollView(
                child: ProjectStatCards(stats: _stats),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        // An overflow is a FlutterError, which fails the test on its own.

        final tiles = [
          for (final icon in _icons)
            tester.getRect(
              find
                  .ancestor(
                    of: find.byIcon(icon),
                    matching: find.byType(Container),
                  )
                  .first,
            ),
        ];
        expect({for (final r in tiles) r.left.round()}, hasLength(columns));
        // A tile that draws its own background fills its row evenly.
        for (var i = 0; i < tiles.length; i += columns) {
          for (final r in tiles.skip(i).take(columns)) {
            expect(r.height, closeTo(tiles[i].height, 0.5));
          }
        }
        for (final e
            in find
                .descendant(
                  of: find.byType(ProjectStatCards),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final paragraph = e.renderObject! as RenderParagraph;
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: paragraph.text.toPlainText(),
          );
        }
      },
    );
  }
}
