import 'package:bambuddy_mobile/core/demo/demo_label_templates.dart';
import 'package:bambuddy_mobile/core/models/label_template.dart';
import 'package:flutter_test/flutter_test.dart';

/// The demo's `/label-templates`, which has to answer what
/// `backend/app/api/routes/label_templates.py` does: the same 409, 404 and 422.
void main() {
  late DemoLabelTemplates demo;

  setUp(() => demo = DemoLabelTemplates());

  Map<String, dynamic> body(String name, [SheetLayout? layout]) => {
    'name': name,
    'layout': (layout ?? SheetLayout.starting).toJson(),
  };

  List<String> names() => [
    for (final row in demo.route('GET', ['label-templates'], {}).body! as List)
      (row as Map)['name'] as String,
  ];

  test('starts with two sheets, in name order', () {
    expect(names(), ['Address labels (A4)', 'Shipping labels (Letter)']);
  });

  test('a save is what the next listing shows', () {
    final created = demo.route('POST', ['label-templates'], body('Avery'));
    expect(created.status, 201);
    expect(names(), contains('Avery'));

    final id = (created.body! as Map)['id'];
    final renamed = demo.route('PUT', ['label-templates', '$id'], body('Zeta'));
    expect(renamed.status, 200);
    expect(names(), isNot(contains('Avery')));
    expect(names(), contains('Zeta'));

    expect(demo.route('DELETE', ['label-templates', '$id'], {}).status, 204);
    expect(names(), isNot(contains('Zeta')));
  });

  test('a name taken ignoring case is a 409, on create and on rename', () {
    expect(
      demo.route('POST', [
        'label-templates',
      ], body('ADDRESS LABELS (a4)')).status,
      409,
    );
    expect(
      demo.route('PUT', [
        'label-templates',
        '2',
      ], body('address labels (a4)')).status,
      409,
    );
  });

  test('a template may be saved again under its own name', () {
    expect(
      demo.route('PUT', [
        'label-templates',
        '1',
      ], body('Address labels (A4)')).status,
      200,
    );
  });

  test('a layout the renderer cannot fit is a 422', () {
    final tooWide = SheetLayout.starting.toJson()..['cols'] = 4;
    expect(
      demo
          .route(
            'POST',
            ['label-templates'],
            {'name': 'Wide', 'layout': tooWide},
          )
          .status,
      422,
    );
  });

  test('an empty or over-long name is a 422', () {
    expect(demo.route('POST', ['label-templates'], body('   ')).status, 422);
    expect(
      demo.route('POST', ['label-templates'], body('x' * 101)).status,
      422,
    );
    expect(
      demo.route('POST', ['label-templates'], body('x' * 100)).status,
      201,
    );
  });

  test('an unknown id is a 404 on a write and on a delete', () {
    expect(demo.route('PUT', ['label-templates', '99'], body('A')).status, 404);
    expect(demo.route('DELETE', ['label-templates', '99'], {}).status, 404);
  });
}
