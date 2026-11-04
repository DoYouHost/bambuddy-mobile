import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/setup/setup_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The screen someone is sent to when their session ends still has their server
/// saved. Making them type the address again is the part of "sign in again"
/// they cannot do from memory: it is an IP and a port on their own LAN.
void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('offers the saved server address to sign in against', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      const SetupScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverProfileOverride(
          const ServerProfile(
            baseUrl: 'http://printers.local:8000',
            authMode: AuthMode.jwt,
          ),
        ),
      ],
    );
    await tester.pump();

    expect(
      find.widgetWithText(TextField, 'http://printers.local:8000'),
      findsOneWidget,
    );
  });

  testWidgets('leaves the field empty on a fresh install', (tester) async {
    await pumpPhone(
      tester,
      const SetupScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        noServerProfileOverride,
      ],
    );
    await tester.pump();

    expect(find.widgetWithText(TextField, 'http'), findsNothing);
  });
}
