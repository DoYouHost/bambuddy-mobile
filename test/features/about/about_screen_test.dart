import 'package:bambuddy_mobile/features/about/about_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
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

  testWidgets('names both versions, in the wording the other two use', (
    tester,
  ) async {
    // The screen someone opens to read a version off was the only one of the
    // three that never named the server, and it called the app's own build a
    // third thing ("Wersja") after the drawer's and the watch's two.
    await pumpPhone(
      tester,
      const AboutScreen(),
      overrides: [
        fakeServerProfileOverride(),
        serverVersionLabelProvider.overrideWith((ref) => '1.2.6b1'),
      ],
    );
    await settle(tester);

    expect(find.text('Aplikacja 0.14.0+2028000'), findsOneWidget);
    expect(find.text('Serwer 1.2.6b1'), findsOneWidget);
  });

  testWidgets('an older server leaves the line, not a gap', (tester) async {
    await pumpPhone(
      tester,
      const AboutScreen(),
      overrides: [
        fakeServerProfileOverride(),
        serverVersionLabelProvider.overrideWith((ref) => null),
      ],
    );
    await settle(tester);

    expect(find.text('Nieznana wersja serwera'), findsOneWidget);
  });

  testWidgets('a fresh install names no server at all', (tester) async {
    // "Server version unknown" under the app's own version reads as a failed
    // connection to a server the user has not added yet. Nothing is the honest
    // line here, and the app version above it still answers what About is for.
    await pumpPhone(
      tester,
      const AboutScreen(),
      overrides: [noServerProfileOverride],
    );
    await settle(tester);

    expect(find.text('Aplikacja 0.14.0+2028000'), findsOneWidget);
    expect(find.text('Nieznana wersja serwera'), findsNothing);
    expect(find.textContaining('Serwer'), findsNothing);
  });
}
