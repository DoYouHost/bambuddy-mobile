import 'package:app_util/app_util.dart';
import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// The demo's `POST /cloud/filament-info`, which the detailed slot rows read.
void main() {
  DemoResult post(Object? body) => DemoBackend.instance.handle(
    'POST',
    Uri.parse('http://demo/api/v1/cloud/filament-info'),
    body,
  );

  test('names the ids it knows and answers every id asked', () {
    final res = post(['GFA00', 'GFG02', 'GFX99']);

    expect(res.status, 200);
    expect(res.body, {
      'GFA00': {'name': 'Bambu PLA Basic', 'k': null},
      'GFG02': {'name': 'Bambu PETG HF', 'k': null},
      'GFX99': {'name': '', 'k': null},
    });
  });

  test('a body that is not a list of ids is an empty answer', () {
    expect(post(const {'ids': 1}).body, isEmpty);
    expect(post(null).body, isEmpty);
  });
}
