import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The palette itself is audited in dash_ui; the accent is ours, so this is
  // the only place a change to it can fail.
  test('the brand accent passes the design system\'s contrast audit', () {
    expect(dashContrastAudit(bambuddyBrand), isEmpty);
  });
}
