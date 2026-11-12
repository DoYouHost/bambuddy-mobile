import 'package:bambuddy_mobile/core/models/label_template.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server refuses an unprintable layout with a 422, so these are the same
/// conditions as `SheetLayout.problem()` in its `label_renderer.py`, one each,
/// in its order — the form names a problem before the request is sent.
void main() {
  SheetLayout layout({
    LabelPageSize page = LabelPageSize.a4,
    double width = 63.5,
    double height = 38.1,
    int columns = 3,
    int rows = 7,
    double top = 15.15,
    double left = 7,
    double columnGap = 2.5,
    double rowGap = 0,
  }) => SheetLayout(
    page: page,
    labelWidthMm: width,
    labelHeightMm: height,
    columns: columns,
    rows: rows,
    topMm: top,
    leftMm: left,
    columnGapMm: columnGap,
    rowGapMm: rowGap,
  );

  group('SheetLayout.problem', () {
    test('the starting layout fits', () {
      expect(SheetLayout.starting.problem, isNull);
    });

    test('a label narrower than 40 mm or shorter than 20 mm is too small', () {
      expect(layout(width: 39.9).problem?.problem, SheetProblem.tooSmall);
      expect(layout(height: 19.9).problem?.problem, SheetProblem.tooSmall);
      expect(
        layout(width: 40, height: 20, columns: 1, rows: 1).problem,
        isNull,
      );
    });

    test('a length over 300 mm is too long, whichever field holds it', () {
      // The grid would not fit either, so the cheaper check has to come first.
      for (final l in [
        layout(width: 300.1, columns: 1),
        layout(height: 300.1, rows: 1),
        layout(top: 300.1),
        layout(left: 300.1),
        layout(columnGap: 300.1),
        layout(rowGap: 300.1),
      ]) {
        expect(l.problem?.problem, SheetProblem.tooLong);
      }
    });

    test('columns and rows are bounded, 1 to 20 and 1 to 40', () {
      expect(layout(columns: 0).problem?.problem, SheetProblem.columns);
      expect(layout(columns: 21).problem?.problem, SheetProblem.columns);
      expect(layout(rows: 0).problem?.problem, SheetProblem.rows);
      expect(layout(rows: 41).problem?.problem, SheetProblem.rows);
    });

    test('a negative margin or gap is refused', () {
      for (final l in [
        layout(top: -1),
        layout(left: -1),
        layout(columnGap: -1),
        layout(rowGap: -1),
      ]) {
        expect(l.problem?.problem, SheetProblem.negative);
      }
    });

    test('a grid wider than the page reports both widths', () {
      // 7 + 3 * 63.5 + 2 * 2.5 = 202.5 fits A4 (210); 4 columns do not.
      final report = layout(columns: 4).problem!;
      expect(report.problem, SheetProblem.tooWide);
      expect(report.sizeMm, closeTo(7 + 4 * 63.5 + 3 * 2.5, 1e-9));
      expect(report.pageMm, 210);
    });

    test('a grid taller than the page reports both heights', () {
      final report = layout(rows: 8).problem!;
      expect(report.problem, SheetProblem.tooTall);
      expect(report.sizeMm, closeTo(15.15 + 8 * 38.1, 1e-9));
      expect(report.pageMm, 297);
    });

    test('the page decides: the same grid is too tall for Letter', () {
      // 279.4 mm tall: 7 rows of 38.1 + 15.15 = 281.85.
      expect(
        layout(page: LabelPageSize.letter).problem?.problem,
        SheetProblem.tooTall,
      );
      expect(layout(page: LabelPageSize.letter, rows: 6).problem, isNull);
    });

    test('a hundredth of a millimetre over is allowed, two are not', () {
      // A sheet measured in inches converts with a few hundredths to spare.
      expect(
        layout(columns: 1, rows: 1, width: 210 - 7 + 0.009).problem,
        isNull,
      );
      expect(
        layout(columns: 1, rows: 1, width: 210 - 7 + 0.02).problem?.problem,
        SheetProblem.tooWide,
      );
    });

    test('too small is named before too long, as the server does', () {
      expect(
        layout(width: 10, top: 999).problem?.problem,
        SheetProblem.tooSmall,
      );
    });
  });

  group('SheetLayout.gridIsDrawable', () {
    test('a grid within the limits is drawn', () {
      expect(SheetLayout.starting.gridIsDrawable, isTrue);
      // Too wide for the page is still a picture: the cells that run off are red.
      expect(layout(columns: 4).gridIsDrawable, isTrue);
      expect(layout(columns: 20, rows: 40).gridIsDrawable, isTrue);
    });

    test('counts past the limits, or none, are not drawn', () {
      for (final l in [
        layout(columns: 21),
        layout(columns: 4000, rows: 4000),
        layout(rows: 41),
        layout(columns: 0),
        layout(rows: -1),
        layout(width: 300.1, columns: 1),
        // A too-small label is named first by `problem`, the length is still too long.
        layout(width: 10, top: 50000),
      ]) {
        expect(l.gridIsDrawable, isFalse);
      }
    });
  });

  group('SheetLayout wire form', () {
    test("toJson uses the server's key names", () {
      expect(SheetLayout.starting.toJson(), {
        'page': 'a4',
        'label_w_mm': 63.5,
        'label_h_mm': 38.1,
        'cols': 3,
        'rows': 7,
        'top_mm': 15.15,
        'left_mm': 7.0,
        'col_gap_mm': 2.5,
        'row_gap_mm': 0.0,
      });
    });

    test('a layout survives its own JSON', () {
      expect(
        SheetLayout.tryFromJson(SheetLayout.starting.toJson()),
        SheetLayout.starting,
      );
    });

    test('whole numbers and strings from the server read as numbers', () {
      final read = SheetLayout.tryFromJson(const {
        'page': 'letter',
        'label_w_mm': 100,
        'label_h_mm': '50.8',
        'cols': 2,
        'rows': 5,
        'top_mm': 12,
        'left_mm': 4.7,
        'col_gap_mm': 0,
        'row_gap_mm': 0,
      })!;
      expect(read.labelWidthMm, 100);
      expect(read.labelHeightMm, 50.8);
      expect(read.page, LabelPageSize.letter);
    });

    test('a page this app does not know is not a layout', () {
      expect(
        SheetLayout.tryFromJson({
          ...SheetLayout.starting.toJson(),
          'page': 'a5',
        }),
        isNull,
      );
    });

    test('capacity counts the grid', () {
      expect(SheetLayout.starting.capacity, 21);
      expect(SheetLayout.starting.sheet.columns, 3);
    });
  });

  group('SavedLabelTemplate.tryFromJson', () {
    test('reads the id, the name and the layout', () {
      final t = SavedLabelTemplate.tryFromJson({
        'id': 4,
        'name': 'Avery',
        'layout': SheetLayout.starting.toJson(),
        'created_at': '2026-11-01T10:00:00',
        'updated_at': '2026-11-01T10:00:00',
      })!;
      expect(t.id, 4);
      expect(t.name, 'Avery');
      expect(t.layout, SheetLayout.starting);
    });

    test('a row without a readable layout is dropped, not thrown', () {
      expect(
        SavedLabelTemplate.tryFromJson(const {'id': 1, 'name': 'x'}),
        isNull,
      );
      expect(
        SavedLabelTemplate.tryFromJson(const {
          'id': 1,
          'name': 'x',
          'layout': {'page': 'a5'},
        }),
        isNull,
      );
    });
  });
}
