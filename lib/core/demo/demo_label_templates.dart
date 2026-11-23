import 'package:app_util/app_util.dart';

import '../models/label_template.dart';
import 'demo_result.dart';

/// The demo's saved label sheets (`/label-templates`): two to pick from, and
/// state, so a save, a rename or a delete is what the next listing shows.
///
/// Answers with the server's own sentences and codes
/// (`backend/app/api/routes/label_templates.py`).
class DemoLabelTemplates {
  static const _duplicate = 'A label template with this name already exists';

  /// Two sheets that differ in everything the form asks: the page, the
  /// proportion of a label and the margins.
  final List<Map<String, dynamic>> _rows = [
    _row(1, 'Address labels (A4)', SheetLayout.starting),
    _row(
      2,
      'Shipping labels (Letter)',
      const SheetLayout(
        page: LabelPageSize.letter,
        labelWidthMm: 101.6,
        labelHeightMm: 50.8,
        columns: 2,
        rows: 5,
        topMm: 12.7,
        leftMm: 4.7,
        columnGapMm: 3.2,
      ),
    ),
  ];
  var _nextId = 3;

  static Map<String, dynamic> _row(int id, String name, SheetLayout layout) {
    final now = isoUtc(DateTime.now());
    return {
      'id': id,
      'name': name,
      'layout': layout.toJson(),
      'created_at': now,
      'updated_at': now,
    };
  }

  /// What `LabelTemplateIn` makes of a body: a name and a layout the renderer
  /// can print, or the 422 detail.
  static ({String name, SheetLayout layout})? _parse(
    Map<String, dynamic> body,
  ) {
    final name = body['name'];
    final layout = body['layout'];
    if (name is! String || layout is! Map<String, dynamic>) return null;
    final trimmed = name.trim();
    final parsed = SheetLayout.tryFromJson(layout);
    if (trimmed.isEmpty ||
        trimmed.length > maxLabelTemplateName ||
        parsed == null ||
        parsed.problem != null) {
      return null;
    }
    return (name: trimmed, layout: parsed);
  }

  /// Same name ignoring case, as the server's `name_key` does.
  bool _taken(String name, {int? except}) => _rows.any(
    (r) =>
        r['id'] != except && '${r['name']}'.toLowerCase() == name.toLowerCase(),
  );

  DemoResult route(
    String method,
    List<String> segments,
    Map<String, dynamic> body,
  ) {
    if (segments.length == 1) {
      if (method == 'GET') {
        final rows = [..._rows]
          ..sort((a, b) => compareIgnoringCase('${a['name']}', '${b['name']}'));
        return demoOk(rows);
      }
      if (method == 'POST') {
        final parsed = _parse(body);
        if (parsed == null) return demoRefuse(422, 'invalid label template');
        if (_taken(parsed.name)) return demoRefuse(409, _duplicate);
        final row = _row(_nextId++, parsed.name, parsed.layout);
        _rows.add(row);
        return (status: 201, body: row);
      }
      return demoNotFound();
    }
    final row = segments.length == 2
        ? rowById(_rows, int.tryParse(segments[1]))
        : null;
    if (row == null) {
      return segments.length == 2
          ? demoRefuse(404, 'Label template not found')
          : demoNotFound();
    }
    if (method == 'PUT') {
      final parsed = _parse(body);
      if (parsed == null) return demoRefuse(422, 'invalid label template');
      if (_taken(parsed.name, except: row['id'] as int)) {
        return demoRefuse(409, _duplicate);
      }
      row['name'] = parsed.name;
      row['layout'] = parsed.layout.toJson();
      row['updated_at'] = isoUtc(DateTime.now());
      return demoOk(row);
    }
    if (method == 'DELETE') {
      _rows.remove(row);
      return (status: 204, body: null);
    }
    return demoNotFound();
  }
}
