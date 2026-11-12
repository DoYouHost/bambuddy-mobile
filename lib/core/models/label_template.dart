/// Custom label sheets and the templates they are saved under (server #3296):
/// `GET/POST/PUT/DELETE /label-templates`, and `layout` on the two label routes.
library;

import 'dart:math' as math;

import 'package:app_util/app_util.dart';

import 'json_utils.dart';

/// The two pages the server lays a sheet on (`PageSize` in `label_renderer.py`).
enum LabelPageSize {
  a4('a4', 210, 297),
  letter('letter', 215.9, 279.4);

  const LabelPageSize(this.wire, this.widthMm, this.heightMm);

  final String wire;
  final double widthMm;
  final double heightMm;

  static LabelPageSize? fromWire(Object? raw) =>
      enumByWire(values, raw, (p) => p.wire);
}

/// Limits of `label_renderer.py`, number for number. The form checks a layout
/// against them while it is typed, so a problem is named before a 422.
const minLabelWidthMm = 40.0;
const minLabelHeightMm = 20.0;
const maxSheetLengthMm = 300.0;
const maxSheetColumns = 20;
const maxSheetRows = 40;

/// Slack the server allows when the grid is checked against the page: a sheet
/// measured in inches converts to millimetres with a few hundredths either way.
const _fitToleranceMm = 0.01;

/// Longest template name (`NAME_MAX_LENGTH`).
const maxLabelTemplateName = 100;

/// Why a layout cannot be printed, in the order the server checks
/// (`SheetLayout.problem`), so the app and the server name the same problem
/// first.
enum SheetProblem {
  tooSmall,
  tooLong,
  columns,
  rows,
  negative,
  tooWide,
  tooTall,
}

/// A layout's first problem, with the two numbers the page-fit ones quote.
typedef SheetProblemReport = ({
  SheetProblem problem,
  double sizeMm,
  double pageMm,
});

/// A sheet of labels as the server takes it (`SheetLayoutSpec`): the page, the
/// size of one label, the grid, and the margins and gaps. Lengths are in
/// millimetres.
class SheetLayout {
  const SheetLayout({
    required this.page,
    required this.labelWidthMm,
    required this.labelHeightMm,
    required this.columns,
    required this.rows,
    required this.topMm,
    required this.leftMm,
    this.columnGapMm = 0,
    this.rowGapMm = 0,
  });

  /// A 3 × 7 grid on A4 — the Avery L7160, the web form's starting point.
  static const starting = SheetLayout(
    page: LabelPageSize.a4,
    labelWidthMm: 63.5,
    labelHeightMm: 38.1,
    columns: 3,
    rows: 7,
    topMm: 15.15,
    leftMm: 7,
    columnGapMm: 2.5,
  );

  /// Null for a page this app does not know, so one unreadable template does
  /// not take the whole list with it.
  static SheetLayout? tryFromJson(Map<String, dynamic> json) {
    final page = LabelPageSize.fromWire(json['page']);
    if (page == null) return null;
    return SheetLayout(
      page: page,
      labelWidthMm: toDouble(json['label_w_mm']),
      labelHeightMm: toDouble(json['label_h_mm']),
      columns: toInt(json['cols']),
      rows: toInt(json['rows']),
      topMm: toDouble(json['top_mm']),
      leftMm: toDouble(json['left_mm']),
      columnGapMm: toDouble(json['col_gap_mm']),
      rowGapMm: toDouble(json['row_gap_mm']),
    );
  }

  final LabelPageSize page;
  final double labelWidthMm;
  final double labelHeightMm;
  final int columns;
  final int rows;
  final double topMm;
  final double leftMm;
  final double columnGapMm;
  final double rowGapMm;

  /// Labels on one sheet; positions are numbered 1..capacity, left to right,
  /// top row first.
  int get capacity => columns * rows;

  /// The grid in the shape the starting-position picker draws.
  ({int columns, int rows, double widthMm, double heightMm}) get sheet => (
    columns: columns,
    rows: rows,
    widthMm: labelWidthMm,
    heightMm: labelHeightMm,
  );

  /// Width and height the grid takes up, margins included.
  (double, double) get extentMm => (
    leftMm + columns * labelWidthMm + (columns - 1) * columnGapMm,
    topMm + rows * labelHeightMm + (rows - 1) * rowGapMm,
  );

  /// The first reason this cannot print, or null. Same rules, in the same
  /// order, as `SheetLayout.problem()` on the server — which refuses a layout
  /// with a 422 — so a form built on it never sends one the server will refuse.
  SheetProblemReport? get problem {
    SheetProblemReport report(SheetProblem p) =>
        (problem: p, sizeMm: 0, pageMm: 0);
    if (labelWidthMm < minLabelWidthMm || labelHeightMm < minLabelHeightMm) {
      return report(SheetProblem.tooSmall);
    }
    final longest = [
      labelWidthMm,
      labelHeightMm,
      topMm,
      leftMm,
      columnGapMm,
      rowGapMm,
    ].reduce(math.max);
    if (longest > maxSheetLengthMm) return report(SheetProblem.tooLong);
    if (columns < 1 || columns > maxSheetColumns) {
      return report(SheetProblem.columns);
    }
    if (rows < 1 || rows > maxSheetRows) return report(SheetProblem.rows);
    if ([topMm, leftMm, columnGapMm, rowGapMm].reduce(math.min) < 0) {
      return report(SheetProblem.negative);
    }
    final (width, height) = extentMm;
    if (width > page.widthMm + _fitToleranceMm) {
      return (
        problem: SheetProblem.tooWide,
        sizeMm: width,
        pageMm: page.widthMm,
      );
    }
    if (height > page.heightMm + _fitToleranceMm) {
      return (
        problem: SheetProblem.tooTall,
        sizeMm: height,
        pageMm: page.heightMm,
      );
    }
    return null;
  }

  /// The body of `layout` in a request, and of a template save.
  Map<String, dynamic> toJson() => {
    'page': page.wire,
    'label_w_mm': labelWidthMm,
    'label_h_mm': labelHeightMm,
    'cols': columns,
    'rows': rows,
    'top_mm': topMm,
    'left_mm': leftMm,
    'col_gap_mm': columnGapMm,
    'row_gap_mm': rowGapMm,
  };

  @override
  bool operator ==(Object other) =>
      other is SheetLayout &&
      other.page == page &&
      other.labelWidthMm == labelWidthMm &&
      other.labelHeightMm == labelHeightMm &&
      other.columns == columns &&
      other.rows == rows &&
      other.topMm == topMm &&
      other.leftMm == leftMm &&
      other.columnGapMm == columnGapMm &&
      other.rowGapMm == rowGapMm;

  @override
  int get hashCode => Object.hash(
    page,
    labelWidthMm,
    labelHeightMm,
    columns,
    rows,
    topMm,
    leftMm,
    columnGapMm,
    rowGapMm,
  );
}

/// A sheet saved under a name (`LabelTemplateResponse`), shared by everyone on
/// the install. Printing never reads it: the print request carries the layout
/// itself.
class SavedLabelTemplate {
  const SavedLabelTemplate({
    required this.id,
    required this.name,
    required this.layout,
  });

  /// Null for a row whose layout this app cannot read (see
  /// [SheetLayout.tryFromJson]).
  static SavedLabelTemplate? tryFromJson(Map<String, dynamic> json) {
    final layout = json['layout'];
    final parsed = layout is Map<String, dynamic>
        ? SheetLayout.tryFromJson(layout)
        : null;
    if (parsed == null) return null;
    return SavedLabelTemplate(
      id: toInt(json['id']),
      name: toStringOrNull(json['name']) ?? '',
      layout: parsed,
    );
  }

  final int id;

  /// Unique ignoring case and Unicode composition: a save under a taken name
  /// is a 409.
  final String name;
  final SheetLayout layout;
}
