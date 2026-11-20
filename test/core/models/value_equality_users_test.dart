import 'package:bambuddy_mobile/core/models/label_template.dart';
import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:bambuddy_mobile/features/gcode/gcode_viewer_page.dart';
import 'package:bambuddy_mobile/features/print_log/print_log_providers.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// One class: [base] builds an instance, each variant differs from it in
/// exactly one field. A field left out of `props` makes its variant equal.
void _value<T extends Object>(
  String name,
  T Function() base,
  Map<String, T> variants,
) {
  group(name, () {
    test('equal fields are equal, with the same hash', () {
      expect(base(), base());
      expect(base().hashCode, base().hashCode);
    });

    for (final MapEntry(key: field, value: other) in variants.entries) {
      test('a different $field is not equal', () {
        expect(other, isNot(base()));
      });
    }

    test('is not equal to another type', () {
      expect(base(), isNot(Object()));
    });
  });
}

final _day = DateTime.utc(2026, 1, 1);

void main() {
  _value<SheetLayout>('SheetLayout', () => SheetLayout.starting, {
    'page': const SheetLayout(
      page: LabelPageSize.letter,
      labelWidthMm: 63.5,
      labelHeightMm: 38.1,
      columns: 3,
      rows: 7,
      topMm: 15.15,
      leftMm: 7,
      columnGapMm: 2.5,
    ),
    'label width': _layout(labelWidthMm: 60),
    'label height': _layout(labelHeightMm: 30),
    'columns': _layout(columns: 2),
    'rows': _layout(rows: 6),
    'top': _layout(topMm: 10),
    'left': _layout(leftMm: 5),
    'column gap': _layout(columnGapMm: 0),
    'row gap': _layout(rowGapMm: 1),
  });

  _value<PrintLogFilters>('PrintLogFilters', () => _filters(), {
    'query': _filters(query: 'benchy'),
    'printer': _filters(printerId: 2),
    'status': _filters(status: 'failed'),
    'username': _filters(username: 'ann'),
    'from': _filters(from: _day),
    'to': _filters(to: _day),
    'sort': _filters(sort: PrintLogSort.values.last),
    'direction': _filters(descending: false),
  });

  _value<StatsFilter>('StatsFilter', () => const StatsFilter(), {
    'range': const StatsFilter(range: StatsRange.last7Days),
    'from': StatsFilter(from: _day),
    'to': StatsFilter(to: _day),
    'creator': const StatsFilter(createdById: 3),
  });

  _value<PipelineRunFilter>('PipelineRunFilter', () => _runFilter(), {
    'pipeline': _runFilter(pipelineId: 1),
    'status': _runFilter(status: 'failed'),
    'printer': _runFilter(targetPrinterId: 2),
    'model class': _runFilter(targetModelClass: 'X1'),
  });

  _value<PresetRef>(
    'PresetRef',
    () => const PresetRef(source: 'local', id: '1'),
    {
      'source': const PresetRef(source: 'cloud', id: '1'),
      'id': const PresetRef(source: 'local', id: '2'),
    },
  );

  // `alive` is true in every constructor, so it cannot differ on its own.
  _value<GcodeViewerReport>(
    'GcodeViewerReport ready',
    () => const GcodeViewerReport.alive(),
    {'ready': const GcodeViewerReport.ready()},
  );
  _value<GcodeViewerReport>(
    'GcodeViewerReport failed',
    () => const GcodeViewerReport.failed(GcodeViewerError.http),
    {
      'error': const GcodeViewerReport.alive(),
      'status': const GcodeViewerReport.failed(
        GcodeViewerError.http,
        status: 404,
      ),
    },
  );
}

SheetLayout _layout({
  double labelWidthMm = 63.5,
  double labelHeightMm = 38.1,
  int columns = 3,
  int rows = 7,
  double topMm = 15.15,
  double leftMm = 7,
  double columnGapMm = 2.5,
  double rowGapMm = 0,
}) => SheetLayout(
  page: LabelPageSize.a4,
  labelWidthMm: labelWidthMm,
  labelHeightMm: labelHeightMm,
  columns: columns,
  rows: rows,
  topMm: topMm,
  leftMm: leftMm,
  columnGapMm: columnGapMm,
  rowGapMm: rowGapMm,
);

PrintLogFilters _filters({
  String query = '',
  int? printerId,
  String? status,
  String? username,
  DateTime? from,
  DateTime? to,
  PrintLogSort sort = PrintLogSort.date,
  bool descending = true,
}) => PrintLogFilters(
  query: query,
  printerId: printerId,
  status: status,
  username: username,
  from: from,
  to: to,
  sort: sort,
  descending: descending,
);

PipelineRunFilter _runFilter({
  int? pipelineId,
  String? status,
  int? targetPrinterId,
  String? targetModelClass,
}) => PipelineRunFilter(
  pipelineId: pipelineId,
  status: status,
  targetPrinterId: targetPrinterId,
  targetModelClass: targetModelClass,
);
