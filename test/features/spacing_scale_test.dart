import 'package:app_guards/app_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spacing in lib/ comes from DashSpace', () {
    final offenders = rawSpacing();
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
