import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:bambuddy_mobile/features/settings/server_settings_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The hub is one entry in the drawer for everything that belongs to the
/// server. What it must not do is inherit the administration gate: that gate
/// answers "no" for an anonymous session and for an API key, and both of those
/// have settings to read — an anonymous one on a server with authentication off
/// has settings to *write*.
void main() {
  Future<void> pumpHub(
    WidgetTester tester, {
    AuthMode authMode = AuthMode.none,
    CurrentUser? user,
    AsyncValue<bool> profileDefaults = const AsyncData(false),
    Map<String, dynamic> serverSettings = const {},
  }) async {
    await pumpPhone(
      tester,
      const ServerSettingsScreen(),
      overrides: [
        fakeServerProfileOverride(authMode: authMode),
        currentUserOverride(user),
        profileDefaultsSupportedProvider.overrideWithValue(profileDefaults),
        serverSettingsRepositoryProvider.overrideWithValue(
          _SettingsRepo(serverSettings),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the profile defaults entry waits for a server that has them', (
    tester,
  ) async {
    await pumpHub(tester, profileDefaults: const AsyncData(true));
    expect(find.text(pl.profileDefaultsTitle), findsOneWidget);
  });

  testWidgets('a server without profile defaults, or one that has not '
      'answered yet, shows no entry', (tester) async {
    await pumpHub(tester);
    expect(find.text(pl.profileDefaultsTitle), findsNothing);

    await pumpHub(tester, profileDefaults: const AsyncLoading());
    expect(find.text(pl.profileDefaultsTitle), findsNothing);
  });

  testWidgets('the pause warning entry is offered only to a server that '
      'answers its key', (tester) async {
    await pumpHub(tester, serverSettings: {'pause_warning_minutes': 5});
    expect(find.text(pl.pauseWarningTitle), findsOneWidget);
  });

  testWidgets('a server that does not send the key shows no pause warning '
      'entry', (tester) async {
    await pumpHub(tester, serverSettings: {'queue_shortest_first': true});
    expect(find.text(pl.pauseWarningTitle), findsNothing);
  });

  testWidgets('an anonymous session gets the settings entries', (tester) async {
    await pumpHub(tester);

    expect(find.text(pl.queueSettingsTitle), findsOneWidget);
    expect(find.text(pl.maintenanceSettingsTitle), findsOneWidget);
    expect(find.text(pl.cloudAccountMenu), findsOneWidget);
    expect(
      find.text(pl.adminTitle),
      findsNothing,
      reason: 'nobody to attribute an account change to',
    );
  });

  testWidgets('an API-key session gets them too', (tester) async {
    await pumpHub(tester, authMode: AuthMode.apiKey);

    expect(find.text(pl.queueSettingsTitle), findsOneWidget);
    expect(
      find.text(pl.adminTitle),
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

    expect(find.text(pl.queueSettingsTitle), findsOneWidget);
    expect(find.text(pl.adminTitle), findsOneWidget);
  });
}

/// The settings a server answers, with nothing to write.
class _SettingsRepo extends ServerSettingsRepository {
  _SettingsRepo(this._settings) : super(Dio());

  final Map<String, dynamic> _settings;

  @override
  Future<Map<String, dynamic>> fetch() async => _settings;
}
