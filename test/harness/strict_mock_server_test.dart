import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every mock server goes through `mockServer` in `test/helpers.dart`, which
/// makes `data:` an exact match. A `DioAdapter(dio: …)` built by hand falls
/// back to the adapter's default, where a body only has to *contain* the
/// mocked keys — `{}` matches anything, and a test asserting what was sent
/// passes whatever else went along.
void main() {
  test('no mock server is built without the exact-body matcher', () {
    final adapter = RegExp(r'\bDioAdapter\(');
    final offenders = [
      for (final dir in ['test', 'integration_test'])
        if (Directory(dir).existsSync())
          ...Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .where((f) => !f.path.endsWith('test/helpers.dart'))
              .where((f) => !f.path.endsWith('strict_mock_server_test.dart'))
              .where((f) => adapter.hasMatch(f.readAsStringSync()))
              .map((f) => f.path),
    ];

    expect(offenders, isEmpty, reason: 'use mockServer(dio) instead');
  });
}
