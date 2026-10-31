import 'package:bambuddy_mobile/core/models/cloud_auth.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/cloud_repository.dart';
import 'package:bambuddy_mobile/features/settings/app_settings_screen.dart';
import 'package:bambuddy_mobile/features/settings/cloud_account_screen.dart';
import 'package:bambuddy_mobile/features/settings/pause_warning_screen.dart';
import 'package:bambuddy_mobile/features/settings/queue_settings_screen.dart';
import 'package:bambuddy_mobile/features/settings/server_settings_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the settings screens that
/// `rendered_guidelines_test.dart` does not reach: the server settings hub, the
/// queue settings (with the notes and the read-only banner they switch on), the
/// Bambu Cloud account (login, code step, signed in) and, on the app settings,
/// the two open appearance selects, the demo-only section and the watch's
/// preset select. The app settings' own three sections are covered there.
/// Not covered: the maintenance settings (its own feature directory), the
/// snackbars a refused write ends in, and the queue settings' load-failure
/// branch, which `serverSettingsProvider` swallows into the empty state below.
void main() {
  _serverSettings();
  _queueSettings();
  _pauseWarning();
  _cloudAccount();
  _appSettings();
}

void _serverSettings() {
  a11ySurface(
    'server settings hub',
    home: () => const ServerSettingsScreen(),
    shows: find.text(pl.queueSettingsTitle),
  );
}

/// The queue block as a current server answers it, with the two masters
/// switchable.
Map<String, dynamic> _queueBlock({bool preheat = true, bool keepWarm = true}) =>
    {
      'require_plate_clear': false,
      'queue_shortest_first': true,
      'queue_max_concurrent_uploads': 4,
      'preheat_enabled': preheat,
      'preheat_max_wait_seconds': 900,
      'preheat_soak_seconds': 300,
      'queue_keep_bed_warm': keepWarm,
      'queue_keep_warm_bed_temp': 90,
      'queue_keep_warm_max_minutes': 120,
      'confirm_outcome_default': true,
      'confirm_outcome_external': false,
      'confirm_good_on_plate_clear': false,
    };

void _queueSettings() {
  a11ySurface(
    'queue settings',
    home: () => const QueueSettingsScreen(),
    shows: find.text(pl.queueSettingsPlateClearTitle),
  );

  // Both notes ("preheat is off", "keep-warm is off") and the greyed rows.
  a11ySurface(
    'queue settings, masters off',
    demo: false,
    overrides: [
      // The notes show only on a form that can be written, and a profile without
      // an auth mode leaves that verdict open.
      fakeServerProfileOverride(authMode: AuthMode.none),
      serverSettingsOverride(_queueBlock(preheat: false, keepWarm: false)),
    ],
    home: () => const QueueSettingsScreen(),
    shows: find.text(pl.queueSettingsPreheatOffNote),
  );

  a11ySurface(
    'queue settings, read-only for an API key',
    demo: false,
    overrides: [
      fakeServerProfileOverride(authMode: AuthMode.apiKey),
      serverSettingsOverride(_queueBlock()),
    ],
    home: () => const QueueSettingsScreen(),
    shows: find.text(pl.queueSettingsReadOnlyApiKey),
  );

  a11ySurface(
    'queue settings, server knows none of them',
    demo: false,
    overrides: [
      noServerProfileOverride,
      serverSettingsOverride(const {'use_slicer_api': true}),
    ],
    home: () => const QueueSettingsScreen(),
    shows: find.text(pl.queueSettingsUnavailable),
  );
}

void _pauseWarning() {
  a11ySurface(
    'pause warning',
    home: () => const PauseWarningScreen(),
    shows: find.text(pl.pauseWarningDesc),
  );

  a11ySurface(
    'pause warning, read-only for an API key',
    demo: false,
    overrides: [
      fakeServerProfileOverride(authMode: AuthMode.apiKey),
      serverSettingsOverride(const {'pause_warning_minutes': 10}),
    ],
    home: () => const PauseWarningScreen(),
    shows: find.text(pl.queueSettingsReadOnlyApiKey),
  );
}

/// Answers the cloud routes from memory: [signedIn] is the status, and a login
/// always asks for a code.
class _Cloud implements CloudRepository {
  @override
  Future<CloudAuthStatus> status() async =>
      const CloudAuthStatus(isAuthenticated: false);

  @override
  Future<CloudLoginResult> login({
    required String email,
    required String password,
    String region = 'global',
  }) async => const CloudLoginResult(
    success: false,
    needsVerification: true,
    tfaKey: 'key',
  );

  @override
  Future<CloudLoginResult> verify({
    required String email,
    required String code,
    String? tfaKey,
    String region = 'global',
  }) async => const CloudLoginResult(success: true);

  @override
  Future<void> logout() async {}
}

void _cloudAccount() {
  a11ySurface(
    'cloud account, login',
    home: () => const CloudAccountScreen(),
    shows: find.text(pl.cloudSignIn),
  );

  a11ySurface(
    'cloud account, code step',
    demo: false,
    overrides: [
      fakeServerProfileOverride(),
      cloudRepositoryProvider.overrideWithValue(_Cloud()),
    ],
    home: () => const CloudAccountScreen(),
    arrange: (tester) async {
      await tester.enterText(byLogId('cloud.email'), 'maker@home.lan');
      await tester.enterText(byLogId('cloud.password'), 'secret');
      await tester.tap(byLogId('cloud.sign_in'));
      await settle(tester);
    },
    shows: find.text(pl.cloudVerify),
  );

  a11ySurface(
    'cloud account, signed in',
    demo: false,
    overrides: [
      fakeServerProfileOverride(),
      cloudAuthStatusProvider.overrideWith(
        (ref) async => const CloudAuthStatus(
          isAuthenticated: true,
          email: 'maker@home.lan',
          region: 'china',
        ),
      ),
    ],
    home: () => const CloudAccountScreen(),
    shows: find.text(pl.cloudSignOut),
  );
}

void _appSettings() {
  for (final (select, option) in [
    ('app_settings.accent', 'app_settings.accent.graphite'),
    ('app_settings.theme_mode', 'app_settings.theme_mode.dark'),
  ]) {
    a11ySurface(
      'app settings, $select menu open',
      demo: false,
      home: () => const AppSettingsScreen(),
      arrange: (tester) async {
        await tester.tap(byLogId(select));
        await settle(tester);
      },
      shows: byLogId(option),
    );
  }

  // Only a demo profile shows the "printing machines" slider.
  a11ySurface(
    'app settings, demo section',
    home: () => const AppSettingsScreen(),
    shows: find.text(pl.demoPrintingCountTitle),
  );

  // Both watch sources off: the preset select appears, then opens.
  Future<void> watchPresets(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: byLogId('app_settings.section'),
        matching: find.byIcon(Icons.watch_outlined),
      ),
    );
    await settle(tester);
    await tester.tap(byLogId('watch_settings.from_phone'));
    await settle(tester);
  }

  a11ySurface(
    'app settings, watch presets',
    demo: false,
    home: () => const AppSettingsScreen(),
    arrange: watchPresets,
    shows: byLogId('watch_settings.accent'),
  );

  a11ySurface(
    'app settings, watch preset menu open',
    demo: false,
    home: () => const AppSettingsScreen(),
    arrange: (tester) async {
      await watchPresets(tester);
      await tester.tap(byLogId('watch_settings.accent'));
      await settle(tester);
    },
    shows: byLogId('watch_settings.accent.orange'),
  );
}
