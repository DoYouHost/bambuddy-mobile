import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/ws_client.dart';
import '../../core/diagnostics/diagnostic_recorder.dart';
import '../../core/diagnostics/log_event.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/battery_optimization.dart';
import '../../core/settings/sign_in_reason.dart';
import '../../core/theme/dash_text.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../admin/admin_screen.dart' show canOpenAdminProvider;
import '../bug_report/recording_banner.dart' show bugReportRoute;
import '../common/dash_progress.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/filter_controls.dart';
import '../notifications/finish_photo_providers.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_search_field.dart';
import 'dashboard_filters.dart';
import 'providers.dart';
import 'smart_plugs_providers.dart';
import '../../core/theme/dash_theme.dart';
import 'widgets/connection_banner.dart';
import 'widgets/connection_mode_chip.dart';
import 'widgets/dashboard_filter_sheet.dart';
import 'widgets/printer_card.dart';
import 'ws_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _query = '';
  late final AppLifecycleListener _lifecycle;

  /// Whether the "sign in again" warning already ran in this launch.
  bool _signInWarned = false;

  /// Whether a check for it is in flight — a resume landing mid-check would
  /// otherwise walk past the guard and open a second dialog.
  bool _signInChecking = false;

  static const _onboardingFlag = 'notif_onboarded';

  @override
  void initState() {
    super.initState();
    // Lifecycle (Model A: background service takes over during background).
    // - Background: if background monitoring is enabled, start foreground service —
    //   its separate isolate is the ONLY notification owner with its own
    //   WS (also catches print START in background). UI goes silent: closes
    //   socket and stops polling (FGS keeps process alive, so timer would keep
    //   ticking and hitting server unnecessarily).
    // - Resume: stop service, REST backfill, reconnect WS UI.
    _lifecycle = AppLifecycleListener(
      onPause: () {
        if (ref.read(bgMonitoringEnabledProvider)) {
          final monitor = ref.read(backgroundMonitorProvider);
          unawaited(
            monitor.start().then((started) {
              // Recorded from here, the one isolate that is certainly able to
              // write. The service's own stream gives up silently in several
              // cases (no writable directory, a session past its five minutes, a
              // platform read that failed), and each of them looks exactly like
              // an app that was never backgrounded. `started` separates those
              // from the case below, where nothing was ever asked to start.
              _logBgService('start', started: started);
              // Already running, so its start-up never ran for this recording
              // (nor for the clock format the UI has just written down) and it
              // has no idea either exists. This is the normal state after the
              // user has swiped the app away once.
              if (!started) {
                monitor.syncDiagnostics();
                monitor.syncClockFormat();
              }
            }),
          );
          // Hand the watch relay over to the FGS isolate. Exactly one
          // responder may listen at a time — a request answered twice is a
          // command executed twice (e.g. double startNext).
          ref.read(wearRelayHandlerProvider).stop();
        }
        ref.read(printerStatusesProvider.notifier).suspend();
        ref.read(dashboardProvider.notifier).pausePolling();
        ref.read(smartPlugsProvider.notifier).pausePolling();
        // Token refresh in background is handled by FGS isolate — UI is silent.
        ref.read(tokenRefresherProvider)?.stop();
        // No thumbnails render in background; FGS cover fetch re-mints reactively.
        ref.read(cameraTokenRefresherProvider)?.stop();
        // The service isolate carries its own from here. Both would poll the
        // same archives and, worse, both write the shared alert memory — a
        // read-modify-write, so the loser's entry is dropped and its photo never
        // reaches the notification.
        final finishPhoto = ref.read(finishPhotoNotifierProvider);
        if (finishPhoto != null) unawaited(finishPhoto.stop());
      },
      onResume: () {
        _logBgService('stop');
        // Take the watch relay and the finish-photo search back only once the
        // FGS isolate is stopped, so neither pair ever overlaps (see onPause).
        unawaited(
          ref.read(backgroundMonitorProvider).stop().then((_) {
            ref.read(wearRelayHandlerProvider).start();
            ref.read(finishPhotoNotifierProvider)?.start();
          }),
        );
        ref.read(dashboardProvider.notifier).resumePolling();
        ref.read(printerStatusesProvider.notifier).resume();
        ref.read(smartPlugsProvider.notifier).resumePolling();
        ref.read(tokenRefresherProvider)?.start();
        ref.read(cameraTokenRefresherProvider)?.start();
        // The background isolate may have met the rejection while we were away.
        unawaited(_maybeWarnSignInRequired());
      },
    );
    // After first render: one-time notification onboarding (permission +
    // request to allow "Unrestricted" battery usage), then the sign-in warning.
    // Sequential so the two never stack dialogs on a first run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_onFirstFrame());
    });
  }

  Future<void> _onFirstFrame() async {
    await _takeOverFromSurvivingService();
    await _maybeOnboardNotifications();
    await _maybeWarnSignInRequired();
  }

  /// Stops a service that outlived the app it was started from.
  ///
  /// Not `onResume`: that fires on a *transition*, and a cold start is already
  /// resumed. A service Android restarted after a swipe-away runs on whatever
  /// it froze at *its* own start-up, and its watch relay answers alongside this
  /// isolate's.
  Future<void> _takeOverFromSurvivingService() async {
    final monitor = ref.read(backgroundMonitorProvider);
    if (!await monitor.isRunning()) return;
    _logBgService('stop_survivor');
    await monitor.stop();
  }

  /// Warns once per app open that the server rejected the remembered login.
  ///
  /// Both places that notice it are invisible to the user — the 401 interceptor
  /// and the background token refresh — and afterwards the app simply stops
  /// loading anything. The one message it would otherwise show is "session
  /// expired", which reads as "sign in with the same password again"; the point
  /// here is that the saved password is the thing that stopped working, and that
  /// the app has stopped replaying it rather than keep spending the server's
  /// failed-attempt budget. Cleared when a profile is saved again
  /// (`ServerProfileNotifier.save`), so it keeps reappearing until then.
  Future<void> _maybeWarnSignInRequired() async {
    // `_signInWarned` cannot stand in for `_signInChecking`: it is only set once
    // the flag turns out to be on, and a check that found it off has to leave
    // the door open for the next resume.
    if (_signInWarned || _signInChecking || !mounted) return;
    _signInChecking = true;
    try {
      // Both writers are other isolates, so this handle still serves the cache
      // the app started with — the rejection it asks about is only on disk.
      await ref.read(sharedPreferencesProvider).reload();
    } finally {
      _signInChecking = false;
    }
    if (!mounted) return;
    final settings = ref.read(settingsRepositoryProvider);
    if (!settings.loadSignInRequired()) return;
    // Once per launch: a resume must not re-open it, but the next open must.
    _signInWarned = true;
    final l10n = AppLocalizations.of(context);
    final signIn = await confirmDialog(
      context,
      title: l10n.signInRequiredTitle,
      // 2FA gets its own wording: the saved password is fine there, and sending
      // the user off to reset it would waste their time on the wrong thing.
      message: switch (settings.loadSignInReason()) {
        SignInReason.credentialsRejected => l10n.signInRequiredBody,
        SignInReason.twoFactorRequired => l10n.signInRequiredTwoFactorBody,
      },
      confirmLabel: l10n.signInRequiredAction,
      cancelLabel: l10n.later,
      icon: Icons.lock_outline,
      id: 'sign_in_required',
    );
    if (signIn && mounted) context.go('/setup');
  }

  /// Hands the background service's lifecycle to the log from the UI side, where
  /// there is always a buffer to write into.
  void _logBgService(String action, {bool? started}) =>
      DiagnosticRecorder.active?.add(
        LogSource.app,
        'bg_service',
        fields: {'action': action, 'started': started},
      );

  Future<void> _maybeOnboardNotifications() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_onboardingFlag) ?? false) return;
    final granted = await _runNotificationOnboarding();
    // Marked done only once it actually landed. Writing the flag before asking
    // spent the one automatic prompt on a run the user may have dismissed by
    // accident — and Android keeps showing its dialog until it is refused twice,
    // so a first "no" is worth another launch rather than permanent silence.
    if (granted) await prefs.setBool(_onboardingFlag, true);
  }

  /// Requests notification permission, and if app is not exempt from battery
  /// optimization — shows a dialog with link to settings.
  ///
  /// `manual` = triggered by button (not auto-onboarding): then on "quiet"
  /// paths (permission denied / already set up) show SnackBar
  /// so button doesn't look dead.
  ///
  /// Answers whether the permission is in hand, which is what decides if the
  /// automatic run counts as done.
  Future<bool> _runNotificationOnboarding({bool manual = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    if (!mounted) return granted;
    if (!granted) {
      if (manual) {
        messenger.snack(l10n.notificationsBlocked);
      }
      return false;
    }
    final battery = BatteryOptimization();
    if (await battery.isIgnoring()) {
      if (manual && mounted) {
        messenger.snack(l10n.notificationsReady);
      }
      return true;
    }
    if (!mounted) return true;
    final open = await confirmDialog(
      context,
      title: l10n.batteryOptTitle,
      message: l10n.batteryOptBody,
      confirmLabel: l10n.batteryOptAllow,
      cancelLabel: l10n.batteryOptLater,
      id: 'battery_opt',
    );
    if (open) await battery.request();
    return true;
  }

  /// Notification menu: background monitoring toggle + re-onboard
  /// (permission/battery). Opened from bell icon.
  void _openNotificationMenu(BuildContext context, AppLocalizations l10n) {
    dashSheet<void>(
      context,
      scrollControlled: false,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer(
              builder: (ctx, ref, _) {
                final enabled = ref.watch(bgMonitoringEnabledProvider);
                return logTag(
                  'notifications_menu.background',
                  SwitchListTile(
                    secondary: const Icon(Icons.sync),
                    title: Text(l10n.bgMonitoringToggle),
                    subtitle: Text(l10n.bgMonitoringSubtitle),
                    value: enabled,
                    onChanged: (v) => _setBgMonitoring(sheetCtx, ref, l10n, v),
                  ),
                );
              },
            ),
            logTag(
              'notifications_menu.events',
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(l10n.notifEventsMenu),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  context.push('/settings/notifications');
                },
              ),
            ),
            logTag(
              'notifications_menu.battery',
              ListTile(
                leading: const Icon(Icons.battery_saver),
                title: Text(l10n.batteryOptMenu),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _runNotificationOnboarding(manual: true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setBgMonitoring(
    BuildContext sheetCtx,
    WidgetRef ref,
    AppLocalizations l10n,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(bgMonitoringEnabledProvider.notifier).set(enabled);
    // Disabling takes effect immediately if service is running; enabling
    // takes effect at next background transition (FGS not needed in foreground).
    if (!enabled) await ref.read(backgroundMonitorProvider).stop();
    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
    messenger.snack(enabled ? l10n.bgMonitoringOn : l10n.bgMonitoringOff);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Session expiry → graceful return to setup, never crash or dead dashboard.
    ref.listen(dashboardProvider.select((s) => s.authExpired), (_, expired) {
      if (expired) {
        ScaffoldMessenger.of(
          context,
        ).snack(l10n.sessionExpired);
        context.go('/setup');
      }
    });

    final state = ref.watch(dashboardProvider);
    final profile = ref.watch(serverProfileProvider);
    final statuses = ref.watch(printerStatusesProvider);
    final filters = ref.watch(dashboardFiltersProvider);
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull;
    final t = DashTokens.of(context);

    // Keep proactive JWT + camera-token refresh alive while dashboard is on
    // screen, and start them (idempotently). Lifecycle pauses/resumes them.
    ref.watch(tokenRefresherProvider)?.start();
    ref.watch(cameraTokenRefresherProvider)?.start();

    // Not read — watched so it exists while this screen (and with it the UI's
    // socket) does. It waits for the finish photo the server attaches after a
    // print, which lands once the print-ended notification is already out.
    ref.watch(finishPhotoNotifierProvider);

    // Full-screen dark/light gradient backdrop behind a transparent Scaffold —
    // gives the seamless "designed screen" look through the app bar.
    return Container(
      decoration: BoxDecoration(gradient: t.backgroundGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: _AppDrawer(profileLabel: profile?.label),
        appBar: loggedAppBar(
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            // Same button AppBar would build implicitly, but named for the log —
            // this screen always has a drawer, so there is no condition to keep.
            leading: logTag('chrome.drawer', const DrawerButton()),
            title: Text(
              l10n.printersTitle,
              style: t.displayLg.copyWith(letterSpacing: -0.5),
            ),
            iconTheme: IconThemeData(color: t.textPrimary),
            actions: [
              const Center(child: ConnectionModeChip()),
              const SizedBox(width: 4),
              logTag(
                'dashboard.add_printer',
                IconButton(
                  tooltip: l10n.addPrinterTitle,
                  color: t.textPrimary,
                  icon: const Icon(Icons.add),
                  onPressed: () => context.push('/printers/add'),
                ),
              ),
              logTag(
                'dashboard.notifications_menu',
                IconButton(
                  tooltip: l10n.batteryOptMenu,
                  color: t.textPrimary,
                  icon: const Icon(Icons.notifications_active_outlined),
                  onPressed: () => _openNotificationMenu(context, l10n),
                ),
              ),
            ],
            // Only friendly profile label (if set) — no URL.
            bottom: profile?.label == null
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(18),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        profile!.label!,
                        style: t.monoMicro,
                      ),
                    ),
                  ),
          ),
        ),
        body: Column(
          children: [
            if (state.stale)
              ConnectionBanner(message: l10n.serverUnreachableStale)
            // WS resuming connection, but polling still provides fresh data —
            // informational banner, not alarming. Don't duplicate "stale" banner.
            else if (_wsReconnecting(wsState))
              ConnectionBanner(
                message: l10n.wsReconnecting,
                tone: BannerTone.info,
              ),
            Expanded(child: _body(context, state, statuses, filters, l10n)),
          ],
        ),
      ),
    );
  }

  /// Show WS banner when actively trying to restore connection —
  /// not on `connected` (silent) or `suspended` (app in background).
  bool _wsReconnecting(WsConnectionState? s) =>
      s == WsConnectionState.connecting || s == WsConnectionState.waitingRetry;

  Widget _body(
    BuildContext context,
    DashboardState state,
    Map<int, PrinterStatus> statuses,
    DashboardFilters filters,
    AppLocalizations l10n,
  ) {
    if (state.loading) {
      return const DashLoading();
    }

    // Initial load failed — nothing to show but error.
    if (state.printers == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(
                state.error?.localized(l10n) ?? l10n.connectFailed,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
                child: Text(l10n.retry),
              ).tagged('dashboard.retry'),
            ],
          ),
        ),
      );
    }

    // Printer composition from polling (roster), with status overlaid from
    // shared statuses map (WS + poll merged in printerStatusesProvider).
    // Missing map entry → status stays from list alone.
    final printers = [
      for (final p in state.printers!)
        statuses.containsKey(p.printer.id)
            ? PrinterWithStatus(
                printer: p.printer,
                status: statuses[p.printer.id],
              )
            : p,
    ];
    final q = _query.trim().toLowerCase();
    final filtered = [
      for (final p in printers)
        if ((q.isEmpty || p.printer.name.toLowerCase().contains(q)) &&
            filters.matches(classifyPrinter(p.status)))
          p,
    ];

    // Show the search + filter row whenever there is more than one printer, or
    // filters are active (so the user can always clear a filter that hid them all).
    final hasSearch = printers.length > 1 || filters.activeCount > 0;
    final filtersActive = filters.activeCount > 0;

    // The header is a pinned, scroll-linked sliver: as the list scrolls the
    // summary card compacts to a thin bar and the search field rolls away,
    // reclaiming space; scrolling back to the top restores both. Being driven
    // by the sliver's own shrinkOffset (not a scroll listener) keeps it smooth.
    return RefreshIndicator(
      onRefresh: () {
        // Also forget what the two history routes last answered. A 403 or 404
        // takes their chart shortcuts off the cards, and with the shortcut gone
        // nothing calls the route again — so a permission granted on the server
        // would otherwise need an app restart to show up. Recreating the
        // repositories drops the latch; the "supported" providers watch them.
        ref.invalidate(heaterHistoryRepositoryProvider);
        ref.invalidate(amsHistoryRepositoryProvider);
        return ref.read(dashboardProvider.notifier).refresh();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _DashHeaderDelegate(
              printers: printers,
              hasSearch: hasSearch,
              hint: l10n.searchPrinters,
              filterCount: filters.activeCount,
              onQuery: (v) => setState(() => _query = v),
              onOpenFilters: () => showDashboardFilterSheet(context),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    printers.isEmpty
                        ? l10n.noPrinters
                        : filtersActive
                            ? l10n.noPrintersMatchFilters
                            : l10n.noSearchResults(_query),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 6),
              sliver: SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => PrinterCard(
                  key: ValueKey(filtered[i].printer.id),
                  item: filtered[i],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Navigation drawer with "app-level" screens (secondary to bottom bar tabs):
/// Statistics, Notifications, change server. Hamburger auto-appears in
/// Dashboard AppBar because Scaffold has `drawer` set.
class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({this.profileLabel});

  final String? profileLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Drawer(
      backgroundColor: t.overlaySurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branded header: app icon in raised tile + name + profile,
          // on a soft accent glow (instead of empty DrawerHeader rect).
          ClipRect(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accentGreen.withValues(alpha: t.isDark ? 0.20 : 0.14),
                    t.accentGreen.withValues(alpha: t.isDark ? 0.06 : 0.04),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Glow — accent circle blurred in top-right corner.
                  Positioned(
                    top: -48,
                    right: -36,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.accentGreen.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(color: t.subCardBorder),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.asset(
                                'assets/icon/icon.png',
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bambuddy',
                                  style: t.display.copyWith(letterSpacing: 0.2),
                                ),
                                const SizedBox(height: 4),
                                _ProfileChip(label: profileLabel),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerTile(
                  icon: Icons.folder_outlined,
                  label: l10n.fileManagerMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/files');
                  },
                  id: 'drawer.files',
                ),
                _DrawerTile(
                  icon: Icons.travel_explore_rounded,
                  label: l10n.makerworldMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/makerworld');
                  },
                  id: 'drawer.makerworld',
                ),
                _DrawerTile(
                  icon: Icons.qr_code_2_rounded,
                  label: l10n.swatchCodesMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/swatches');
                  },
                  id: 'drawer.swatches',
                ),
                _DrawerTile(
                  icon: Icons.folder_special_outlined,
                  label: l10n.projectsMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/projects');
                  },
                  id: 'drawer.projects',
                ),
                _DrawerTile(
                  icon: Icons.bar_chart_rounded,
                  label: l10n.menuStatistics,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/stats');
                  },
                  id: 'drawer.stats',
                ),
                _DrawerTile(
                  icon: Icons.tune_rounded,
                  label: l10n.notifEventsMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/settings/notifications');
                  },
                  id: 'drawer.notifications',
                ),
                // Administration — accounts, groups and API keys behind one
                // entry. Only for an identity the server named and granted at
                // least one of the three read permissions: a server with
                // authentication off has nobody to show any of it to, and an
                // API key is refused all three outright.
                if (ref.watch(canOpenAdminProvider))
                  _DrawerTile(
                    icon: Icons.admin_panel_settings_outlined,
                    label: l10n.adminMenu,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/admin');
                    },
                    id: 'drawer.admin',
                  ),
                const Divider(indent: 16, endIndent: 16, height: 16),
                _DrawerTile(
                  icon: Icons.cloud_outlined,
                  label: l10n.cloudAccountMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/settings/cloud');
                  },
                  id: 'drawer.cloud',
                ),
                _DrawerTile(
                  icon: Icons.swap_horiz_rounded,
                  label: l10n.changeServer,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmChangeServer(context, ref, l10n);
                  },
                  id: 'drawer.change_server',
                ),
                _DrawerTile(
                  icon: Icons.bug_report_outlined,
                  label: l10n.bugReportMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push(bugReportRoute);
                  },
                  id: 'drawer.bug_report',
                ),
                _DrawerTile(
                  icon: Icons.info_outline_rounded,
                  label: l10n.aboutMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/about');
                  },
                  id: 'drawer.about',
                ),
              ],
            ),
          ),
          // Footer with version — read from package metadata (like About screen).
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.print_rounded, size: 14, color: t.textTertiary),
                  const SizedBox(width: 6),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) => Text(
                      snap.hasData
                          ? 'Bambuddy v${snap.data!.version}+${snap.data!.buildNumber}'
                          : 'Bambuddy',
                      style: t.labelSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Confirmation repeat for server change — clearing profile navigates to
  /// `/setup` via router. Kept with drawer to not depend on Dashboard state methods.
  Future<void> _confirmChangeServer(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    // Read the notifier up front: the caller pops the drawer before calling us,
    // so this `_AppDrawer` (a ConsumerWidget) is disposed during the dialog
    // await — touching `ref` afterwards throws "Cannot use ref after dispose".
    final profiles = ref.read(serverProfileProvider.notifier);
    final confirmed = await confirmDialog(
      context,
      title: l10n.changeServerQuestion,
      message: l10n.changeServerWarning,
      confirmLabel: l10n.change,
      id: 'change_server',
    );
    if (confirmed) {
      await profiles.clear();
    }
  }
}

/// Profile label (server address) as gentle "chip" under app name.
/// When no profile — hide to not leave blank space.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null) return const SizedBox.shrink();
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_rounded, size: 13, color: t.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.label.copyWith(color: t.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawer item in M3 style — rounded "pill" shape with ripple,
/// tinted icon tile and chevron suggesting navigation. Optional `tint`
/// highlights item (e.g. change server). Extracted for list brevity.
class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.id,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Name for the diagnostic log; the visible label is localized and is not
  /// recorded.
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: logTag(
          id,
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.accentGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 21, color: t.accentGreenInk),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: t.bodyStrong,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: t.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned, scroll-linked dashboard header: the summary card compacts and the
/// search field rolls away as the list scrolls. All motion derives from the
/// sliver's [shrinkOffset], so it tracks the finger exactly (no jank/jumps).
class _DashHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DashHeaderDelegate({
    required this.printers,
    required this.hasSearch,
    required this.hint,
    required this.filterCount,
    required this.onQuery,
    required this.onOpenFilters,
  });

  final List<PrinterWithStatus> printers;
  final bool hasSearch;
  final String hint;
  final int filterCount;
  final ValueChanged<String> onQuery;
  final VoidCallback onOpenFilters;

  // Heights carry generous slack; content is clipped, never overflowed.
  static const double _statusFull = 60;
  static const double _statusCompact = 44;
  static const double _searchH = 66;

  @override
  double get maxExtent => _statusFull + (hasSearch ? _searchH : 0);

  @override
  double get minExtent => _statusCompact;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final range = maxExtent - minExtent;
    final extent = (maxExtent - shrinkOffset).clamp(minExtent, maxExtent);
    final shrink = range <= 0
        ? 1.0
        : ((maxExtent - extent) / range).clamp(0.0, 1.0);
    final searchH = hasSearch ? _searchH * (1 - shrink) : 0.0;
    final statusH = extent - searchH;
    // Fades in as soon as the list starts sliding under the bar; at the very
    // top it stays clear so the background gradient shows through untouched.
    final bgAlpha = (shrink * 2).clamp(0.0, 1.0);
    final column = Column(
      children: [
        SizedBox(
          height: statusH,
          child: _SummaryHeader(printers: printers, shrink: shrink),
        ),
        if (hasSearch)
          SizedBox(
            height: searchH,
            // Render the field at full size and clip as the row shrinks, so
            // the field itself never reflows — only the reveal changes.
            child: ClipRect(
              child: OverflowBox(
                minHeight: _searchH,
                maxHeight: _searchH,
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: (1 - shrink * 1.4).clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Expanded(
                            child: DashSearchField(
                              id: 'dashboard.search',
                              hintText: hint,
                              onChanged: onQuery,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterButton(
                            count: filterCount,
                            tooltip: AppLocalizations.of(context)
                                .dashboardFilters,
                            id: 'dashboard.filters',
                            onTap: onOpenFilters,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (bgAlpha < 0.01) return ClipRect(child: column);

    // Fully opaque fill spanning the whole bar, edge to edge — the card alone
    // can't hide the list, tiles would still slide through the gutters around
    // it. It paints the screen's own background gradient (a flat color can't
    // match it and shows as a patch against the transparent app bar above).
    return ClipRect(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: _HeaderBackdrop(opacity: bgAlpha)),
          column,
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DashHeaderDelegate old) =>
      old.printers != printers ||
      old.hasSearch != hasSearch ||
      old.hint != hint ||
      old.filterCount != filterCount;
}

/// Opaque backdrop for the pinned header. A flat color can't match the screen's
/// radial [DashTokens.backgroundGradient] — it reads as a patch against the
/// transparent app bar above it. So this paints that very gradient, shaded for
/// the whole screen, letting the bar continue the backdrop seamlessly while
/// still hiding the list scrolling behind it.
class _HeaderBackdrop extends LeafRenderObjectWidget {
  const _HeaderBackdrop({required this.opacity});

  /// Fades the fill in as the list starts sliding under; at 0 the bar is clear.
  final double opacity;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeaderBackdrop(
        gradient: DashTokens.of(context).backgroundGradient,
        screenSize: MediaQuery.sizeOf(context),
        opacity: opacity,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderHeaderBackdrop r) {
    r
      ..gradient = DashTokens.of(context).backgroundGradient
      ..screenSize = MediaQuery.sizeOf(context)
      ..opacity = opacity;
  }
}

/// Aligning the gradient needs this box's position on screen, and that can't be
/// derived up front: the app bar above varies in height (status bar inset, and
/// the profile band that only some builds show). So measure it at paint time.
class _RenderHeaderBackdrop extends RenderBox {
  // Fields are private (they back repainting setters), so they take plain
  // params rather than initializing formals.
  // ignore_for_file: prefer_initializing_formals
  _RenderHeaderBackdrop({
    required Gradient gradient,
    required Size screenSize,
    required double opacity,
  }) : _gradient = gradient,
       _screenSize = screenSize,
       _opacity = opacity;

  Gradient _gradient;
  set gradient(Gradient v) {
    if (v == _gradient) return;
    _gradient = v;
    markNeedsPaint();
  }

  Size _screenSize;
  set screenSize(Size v) {
    if (v == _screenSize) return;
    _screenSize = v;
    markNeedsPaint();
  }

  double _opacity;
  set opacity(double v) {
    if (v == _opacity) return;
    _opacity = v;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Screen origin in local paint coordinates: our own screen position maps
    // back to where we are being painted.
    final origin = offset - localToGlobal(Offset.zero);
    final screenRect = origin & _screenSize;
    final paint = Paint()..shader = _gradient.createShader(screenRect);
    // Paint alpha modulates the shader — no save-layer needed.
    if (_opacity < 1) paint.color = paint.color.withValues(alpha: _opacity);
    context.canvas.drawRect(offset & size, paint);
  }
}

/// Summary at top of list: how many printers are working and which
/// will be free soonest (least remaining time). A single card that morphs
/// continuously via [shrink] (0 = full, 1 = compact) — no cross-fade, so the
/// intermediate states stay clean (no doubled text).
class _SummaryHeader extends ConsumerWidget {
  const _SummaryHeader({required this.printers, this.shrink = 0});

  final List<PrinterWithStatus> printers;

  /// 0 = full card, 1 = compact. Drives the top margin and fades out the
  /// "next available" detail; the card height itself is set by the parent.
  final double shrink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    // Total power across farm from smart plugs (separate polling lane).
    final hasPlugs = ref.watch(smartPlugsProvider.select((s) => s.hasAnyPlug));
    final totalPowerW = ref.watch(
      smartPlugsProvider.select((s) => s.totalPowerW),
    );
    final active =
        printers
            .where(
              (p) =>
                  (p.status?.connected ?? false) &&
                  (p.status?.isPrinting ?? false),
            )
            .toList()
          ..sort(
            (a, b) => (a.status!.remainingTime ?? 1 << 30).compareTo(
              b.status!.remainingTime ?? 1 << 30,
            ),
          );

    final next = active.isEmpty ? null : active.first;
    final dotColor = active.isEmpty ? t.textTertiary : t.accentGreen;

    final nextOpacity = (1 - shrink * 1.8).clamp(0.0, 1.0);
    return Container(
      // The card fills the height its parent allots (which shrinks with the
      // scroll); the row stays vertically centred, so there is no vertical
      // padding to animate and never any overflow. The bottom margin grows as
      // it collapses, adding a gap between the pinned bar and the list (when
      // expanded the search field below provides that spacing instead).
      margin: EdgeInsets.fromLTRB(16, 10 - 4 * shrink, 16, 8 * shrink),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 8),
          Text(
            active.isEmpty
                ? l10n.noActivePrints
                : l10n.printingCount(active.length),
            style: t.body.copyWith(color: active.isEmpty ? t.textSecondary : t.textPrimary),
          ),
          if (next != null) ...[
            const SizedBox(width: 12),
            // Fades out as the card collapses (kept in the tree so its space
            // stays reserved and the power chip doesn't jump).
            Flexible(
              child: Opacity(
                opacity: nextOpacity,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: l10n.nextAvailableLabel),
                      TextSpan(
                        text: next.printer.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: _nextSuffix(l10n, next)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSoft.copyWith(color: t.textSecondary),
                ),
              ),
            ),
          ],
          if (hasPlugs) ...[
            if (next == null) const Spacer() else const SizedBox(width: 12),
            Tooltip(
              message: l10n.totalPowerTooltip,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, size: 15, color: t.accentGreenInk),
                  const SizedBox(width: 4),
                  Text(
                    l10n.powerWatts(totalPowerW.round()),
                    style: t.monoValue.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _nextSuffix(AppLocalizations l10n, PrinterWithStatus next) {
    final p = next.status?.progress;
    final r = next.status?.remainingTime;
    final parts = [
      if (p != null) '${p.toStringAsFixed(0)}%',
      if (r != null) formatMinutes(l10n, r),
    ];
    return parts.isEmpty ? '' : ' (${parts.join(' · ')})';
  }
}
