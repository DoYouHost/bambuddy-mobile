import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import 'core/format/system_clock_sync.dart';
import 'core/notifications/background_api.dart';
import 'core/notifications/hms_actions.dart';
import 'core/notifications/hms_stop_request.dart';
import 'core/theme/dash_theme.dart';
import 'features/bug_report/recording_banner.dart';
import 'features/common/confirm_dialog.dart';
import 'features/common/dash_snack.dart';
import 'features/dashboard/controls_providers.dart';
import 'features/dashboard/providers.dart';
import 'features/inventory/inventory_screen.dart' show scanSpoolFlow;
import 'l10n/app_localizations.dart';
import 'l10n/error_messages.dart';
import 'providers.dart';
import 'router.dart';

class BambuddyApp extends ConsumerStatefulWidget {
  const BambuddyApp({super.key});

  @override
  ConsumerState<BambuddyApp> createState() => _BambuddyAppState();
}

class _BambuddyAppState extends ConsumerState<BambuddyApp> {
  StreamSubscription<Uri?>? _widgetClickSub;
  StreamSubscription<HmsStopRequest>? _hmsStopSub;
  // Guard against multiple scanner triggers from one widget tap (cold start may
  // get URI from both initiallyLaunched and stream).
  bool _scanInFlight = false;
  bool _hmsStopInFlight = false;

  @override
  void initState() {
    super.initState();
    // Home screen widget taps: cold start (initiallyLaunched) and when app alive
    // (stream). Both carry deep-link `bambuddy://widget?...`.
    _widgetClickSub = HomeWidget.widgetClicked.listen(_onWidgetUri);
    unawaited(HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetUri));
    // "Stop printing" tapped on an HMS notification. Same two entrances as the
    // widget above: the stream while the app runs, the launch intent when the
    // tap is what started it.
    _hmsStopSub = hmsStopRequests.listen(_onHmsStopRequest);
    unawaited(_onNotificationLaunch());
    // Hand the current profile to a paired Wear OS watch on launch so it can
    // configure itself without the user typing anything. No-ops without a watch.
    final profile = ref.read(serverProfileProvider);
    if (profile != null) {
      unawaited(ref.read(watchConfigSyncProvider).push(profile));
    }
    // Answer watch relay requests for as long as the app lives (plan 05).
    unawaited(ref.read(wearRelayHandlerProvider).start());
  }

  @override
  void dispose() {
    _widgetClickSub?.cancel();
    _hmsStopSub?.cancel();
    super.dispose();
  }

  /// A notification button that started the app. Its tap never reaches
  /// `onDidReceiveNotificationResponse` — there was no engine to receive it —
  /// so the plugin keeps it on the launch intent and hands it over here. Only
  /// an action with `opensApp` can be in there: every other one is delivered to
  /// the background isolate and never launches anything.
  Future<void> _onNotificationLaunch() async {
    try {
      final launch = await FlutterLocalNotificationsPlugin()
          .getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (response != null) await handleNotificationAction(response);
    } on Object {
      // A platform without the plugin (tests, desktop) has no launch details
      // and nothing to recover — the live paths above are unaffected.
    }
    _onHmsStopRequest(takeHmsStop());
  }

  /// Ask before abandoning the print, then send the action the notification
  /// carried. Runs on a post-frame callback for the same reason the scanner
  /// does: a cold start reaches here before there is a navigator to show a
  /// dialog on.
  void _onHmsStopRequest(HmsStopRequest? request) {
    if (request == null || _hmsStopInFlight) return;
    if (ref.read(serverProfileProvider) == null) return;
    _hmsStopInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = rootNavigatorKey.currentContext;
      if (context == null) {
        _hmsStopInFlight = false;
        return;
      }
      try {
        final l10n = AppLocalizations.of(context);
        final confirmed = await confirmDialog(
          context,
          title: l10n.hmsStopConfirmTitle,
          message: l10n.hmsStopConfirmBody(_printerName(request.printerId)),
          confirmLabel: l10n.hmsStopConfirmAction,
          destructive: true,
          id: 'notif.hms_stop_confirm',
        );
        if (!confirmed || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final result = await ref
            .read(controlsProvider.notifier)
            .executeHmsAction(
              request.printerId,
              printError: request.fullCode,
              action: hmsStopAction,
              jobId: request.jobId,
            );
        messenger.snack(
          result.messageFor(l10n) ?? l10n.hmsActionSent,
          clearQueue: true,
        );
      } finally {
        _hmsStopInFlight = false;
      }
    });
  }

  /// The dialog names the printer the fault belongs to. The roster is whatever
  /// the dashboard last loaded; on a cold start it may not be there yet, and an
  /// id is a poorer name but an honest one.
  String _printerName(int printerId) {
    final printers = ref.read(dashboardProvider).printers;
    final match = printers
        ?.where((p) => p.printer.id == printerId)
        .map((p) => p.printer.name)
        .firstOrNull;
    return match ?? '#$printerId';
  }

  void _onWidgetUri(Uri? uri) {
    if (uri == null) return;
    if (uri.queryParameters['action'] == 'scan') {
      _triggerSpoolScan();
    }
  }

  /// Open spool scanner triggered from widget. Requires configured profile
  /// (without it router keeps /setup anyway). Wait for ready navigator — on cold
  /// start first frame may not exist yet.
  void _triggerSpoolScan() {
    if (_scanInFlight) return;
    if (ref.read(serverProfileProvider) == null) return;
    _scanInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = rootNavigatorKey.currentContext;
      if (context == null) {
        _scanInFlight = false;
        return;
      }
      // Land on Filaments tab, then open scanner.
      context.go('/inventory');
      try {
        await scanSpoolFlow(context, ref);
      } finally {
        _scanInFlight = false;
      }
    });
  }

  /// Kept on disk for the foreground service isolate, which formats the ETA in
  /// its notifications and has no way to read the 24-hour switch itself.
  Future<void> _rememberClockFormat(bool use24Hour) => publishSystemClock(
    use24Hour,
    settings: ref.read(settingsRepositoryProvider),
    monitor: ref.read(backgroundMonitorProvider),
  );

  @override
  Widget build(BuildContext context) {
    // Re-push to the watch whenever the profile changes (new server, login,
    // "change server"). Best-effort; silently no-ops when no watch is paired.
    ref.listen(serverProfileProvider, (_, next) {
      if (next != null) {
        unawaited(ref.read(watchConfigSyncProvider).push(next));
      }
    });
    // Notifications handled ONLY by background isolate (foreground service);
    // foreground status shown by UI itself, so no monitor here.
    return MaterialApp.router(
      title: 'Bambuddy',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // App follows system setting; dark theme like PWA.
      themeMode: ThemeMode.system,
      // Locale auto-detected from system; en = fallback.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      // Recording controls have to outlive the report screen — the bug gets
      // reproduced on the dashboard, not there. Wrapping here puts the bar
      // above every route, pushed ones included.
      builder: (context, child) => SystemClockSync(
        onChanged: (use24Hour) => unawaited(_rememberClockFormat(use24Hour)),
        child: RecordingBannerScaffold(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

ThemeData _theme(Brightness brightness) => buildDashThemeData(brightness);
