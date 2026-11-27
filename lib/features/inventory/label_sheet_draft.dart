import 'package:app_util/app_util.dart';

import '../../core/models/label_template.dart';

/// The custom-sheet form as it is typed: every number is still text, so a
/// half-typed "3." or an emptied box is a state of the form, not a lost value.
///
/// Pure, so what a person may type — a comma for the decimal point, a blank, a
/// letter — is tested without a widget.
class SheetLayoutDraft {
  const SheetLayoutDraft({
    required this.page,
    required this.labelWidth,
    required this.labelHeight,
    required this.columns,
    required this.rows,
    required this.top,
    required this.left,
    required this.columnGap,
    required this.rowGap,
  });

  factory SheetLayoutDraft.fromLayout(SheetLayout l) => SheetLayoutDraft(
    page: l.page,
    labelWidth: mmText(l.labelWidthMm),
    labelHeight: mmText(l.labelHeightMm),
    columns: '${l.columns}',
    rows: '${l.rows}',
    top: mmText(l.topMm),
    left: mmText(l.leftMm),
    columnGap: mmText(l.columnGapMm),
    rowGap: mmText(l.rowGapMm),
  );

  final LabelPageSize page;
  final String labelWidth;
  final String labelHeight;
  final String columns;
  final String rows;
  final String top;
  final String left;
  final String columnGap;
  final String rowGap;

  /// The layout these texts describe, or null while any of them is blank or not
  /// a number — columns and rows must be whole. Whether it can be printed is
  /// [SheetLayout.problem]'s to say, so the two kinds of "no" stay apart.
  SheetLayout? get layout {
    final width = parseUserDecimal(labelWidth);
    final height = parseUserDecimal(labelHeight);
    final cols = parseUserInt(columns);
    final rowCount = parseUserInt(rows);
    final topMargin = parseUserDecimal(top);
    final leftMargin = parseUserDecimal(left);
    final colGap = parseUserDecimal(columnGap);
    final rowGapMm = parseUserDecimal(rowGap);
    if (width == null ||
        height == null ||
        cols == null ||
        rowCount == null ||
        topMargin == null ||
        leftMargin == null ||
        colGap == null ||
        rowGapMm == null) {
      return null;
    }
    return SheetLayout(
      page: page,
      labelWidthMm: width,
      labelHeightMm: height,
      columns: cols,
      rows: rowCount,
      topMm: topMargin,
      leftMm: leftMargin,
      columnGapMm: colGap,
      rowGapMm: rowGapMm,
    );
  }
}

/// A length as a field shows it: "63.5", and "7" rather than "7.0". Every digit
/// is kept, so a template saved without being touched is saved as it was.
String mmText(double mm) {
  final text = '$mm';
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
