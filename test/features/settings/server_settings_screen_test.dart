import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/settings/server_settings_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The hub is one entry in the drawer for everything that belongs to the
/// server. What it must not do is inherit the administration gate: that gate
/// answers "no" for an anonymous session and for an API key, and both of those
/// have settings to read — an anonymous one on a server with authentication off
/// has settings to *write*.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<void> pumpHub(
    WidgetTester tester, {
    AuthMode authMode = AuthMode.none,
    CurrentUser? user,
  }) async {
    await pumpPhone(
      tester,
      const ServerSettingsScreen(),
      overrides: [
        fakeServerProfileOverride(authMode: authMode),
        currentUserOverride(user),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an anonymous session gets the settings entries', (tester) async {
    await pumpHub(tester);

    expect(find.text(l10n.queueSettingsTitle), findsOneWidget);
    expect(find.text(l10n.maintenanceSettingsTitle), findsOneWidget);
    expect(find.text(l10n.cloudAccountMenu), findsOneWidget);
    expect(
      find.text(l10n.adminTitle),
      findsNothing,
      reason: 'nobody to attribute an account change to',
    );
  });

  testWidgets('an API-key session gets them too', (tester) async {
    await pumpHub(tester, authMode: AuthMode.apiKey);

    expect(find.text(l10n.queueSettingsTitle), findsOneWidget);
    expect(
      find.text(l10n.adminTitle),
      findsNothing,
      reason: 'a key is refused every administrative permission',
    );
  });

  testWidgets('an admin gets administration as one more entry', (tester) async {
    await pumpHub(
      tester,
      authMode: AuthMode.jwt,
      user: const CurrentUser(id: 1, username: 'ola', isAdmin: true),
    );

    expect(find.text(l10n.queueSettingsTitle), findsOneWidget);
    expect(find.text(l10n.adminTitle), findsOneWidget);
  });
}
