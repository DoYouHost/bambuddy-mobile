import 'package:bambuddy_mobile/core/models/label_template.dart';
import 'package:bambuddy_mobile/features/inventory/label_sheet_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SheetLayoutDraft draft({
    String width = '63.5',
    String height = '38.1',
    String columns = '3',
    String rows = '7',
    String top = '15.15',
    String left = '7',
    String columnGap = '2.5',
    String rowGap = '0',
    LabelPageSize page = LabelPageSize.a4,
  }) => SheetLayoutDraft(
    page: page,
    labelWidth: width,
    labelHeight: height,
    columns: columns,
    rows: rows,
    top: top,
    left: left,
    columnGap: columnGap,
    rowGap: rowGap,
  );

  group('SheetLayoutDraft.layout', () {
    test('typed numbers make the layout they spell', () {
      expect(draft().layout, SheetLayout.starting);
    });

    test('a comma is a decimal point, as the phone keyboard types it', () {
      expect(
        draft(width: '63,5', top: '15,15', columnGap: '2,5').layout,
        SheetLayout.starting,
      );
    });

    test('surrounding spaces do not matter', () {
      expect(
        draft(width: ' 63.5 ', columns: ' 3').layout,
        SheetLayout.starting,
      );
    });

    test('a blank field is no layout yet', () {
      for (final d in [
        draft(width: ''),
        draft(height: '  '),
        draft(columns: ''),
        draft(rows: ''),
        draft(top: ''),
        draft(left: ''),
        draft(columnGap: ''),
        draft(rowGap: ''),
      ]) {
        expect(d.layout, isNull);
      }
    });

    test('text that is no number is no layout', () {
      expect(draft(width: 'wide').layout, isNull);
      expect(draft(top: '1.2.3').layout, isNull);
      expect(draft(left: 'Infinity').layout, isNull);
      expect(draft(rowGap: 'NaN').layout, isNull);
    });

    test('columns and rows are whole numbers', () {
      expect(draft(columns: '2.5').layout, isNull);
      expect(draft(rows: '3,5').layout, isNull);
    });

    test('a number the server will refuse is still a layout', () {
      // "Does it fit" is the layout's own question, not the draft's.
      final layout = draft(columns: '99', top: '-4').layout!;
      expect(layout.columns, 99);
      expect(layout.problem, isNotNull);
    });

    test('the page is carried through', () {
      expect(
        draft(page: LabelPageSize.letter).layout!.page,
        LabelPageSize.letter,
      );
    });
  });

  group('SheetLayoutDraft.fromLayout', () {
    test('a layout reads back as itself', () {
      expect(
        SheetLayoutDraft.fromLayout(SheetLayout.starting).layout,
        SheetLayout.starting,
      );
    });

    test(
      'a whole length has no trailing zero, a fraction keeps its digits',
      () {
        final d = SheetLayoutDraft.fromLayout(SheetLayout.starting);
        expect(d.left, '7');
        expect(d.labelWidth, '63.5');
        expect(d.rowGap, '0');
        expect(d.columns, '3');
      },
    );
  });

  group('mmText', () {
    test('drops a whole number\'s ".0" and keeps every other digit', () {
      expect(mmText(100), '100');
      expect(mmText(10), '10');
      expect(mmText(0), '0');
      expect(mmText(0.5), '0.5');
      expect(mmText(66.675), '66.675');
      expect(mmText(215.9), '215.9');
    });
  });
}
