import 'package:bambuddy_mobile/features/about/about_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'bambuddy',
      packageName: 'page.codeberg.morganmlgman.bambuddy_mobile',
      version: '0.14.0',
      buildNumber: '2028000',
      buildSignature: '',
    );
  });

  testWidgets('the version comes off the shared reader', (tester) async {
    // The screen had its own `PackageInfo` future in a `State`; it now reads
    // the same provider the two footers do, and this is the only test that
    // would notice the About screen being left behind.
    await pumpPhone(tester, const AboutScreen());
    await settle(tester);

    expect(find.text('Wersja 0.14.0+2028000'), findsOneWidget);
  });
}
