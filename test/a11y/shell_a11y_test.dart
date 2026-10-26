import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/router.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the navigation shell, on the app's
/// own router over the demo backend: the bottom bar with each of its five tabs
/// selected (the demo gives the queue and maintenance tabs their badges). What
/// each tab holds is measured as part of the tab, so a violation inside a tab's
/// own screen shows up here as well as in that feature's file. Not covered here:
/// the drawer and its "Change server" confirmation, which `dashboard_a11y_test`
/// already measures, and the pages the drawer opens (each is its feature's).
void main() {
  for (final (index, name) in [
    (0, 'dashboard'),
    (1, 'queue'),
    (2, 'archive'),
    (3, 'maintenance'),
    (4, 'filaments'),
  ]) {
    a11ySurface(
      'shell, $name tab',
      overrides: _appOverrides,
      home: () => const _App(),
      arrange: index == 0
          ? null
          : (tester) async {
              await tester.tap(byLogId(_navIds[index]));
              await a11ySettle(tester, const Duration(seconds: 2));
            },
      shows: byLogId(_navIds[index]),
    );
  }
}

const _navIds = [
  'nav.dashboard',
  'nav.queue',
  'nav.archive',
  'nav.maintenance',
  'nav.filaments',
];

/// What the dashboard needs that the demo backend cannot answer: the platform
/// notification service, the foreground service and the credential store.
final _appOverrides = [
  notificationServiceProvider.overrideWithValue(RecordingNotifications()),
  inertBackgroundMonitorOverride,
  credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
];

/// The app's router in a MaterialApp of its own, wearing the harness's theme
/// the way the tour's inner app does. The harness takes a `home`, and the shell
/// only exists under a router.
class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late final GoRouter _router = buildAppRouter(
    keys: newNavigatorKeys(),
    initialLocation: '/',
    hasProfile: true,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    theme: Theme.of(context),
    locale: Localizations.localeOf(context),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: _router,
  );
}
