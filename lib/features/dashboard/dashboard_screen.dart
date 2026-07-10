import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/ws_client.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/battery_optimization.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import 'providers.dart';
import 'smart_plugs_providers.dart';
import '../../core/theme/dash_theme.dart';
import 'widgets/connection_banner.dart';
import 'widgets/connection_mode_chip.dart';
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
          ref.read(backgroundMonitorProvider).start();
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
      },
      onResume: () {
        // Take the watch relay back only once the FGS isolate is stopped, so
        // the two responders never overlap (see onPause).
        unawaited(ref
            .read(backgroundMonitorProvider)
            .stop()
            .then((_) => ref.read(wearRelayHandlerProvider).start()));
        ref.read(dashboardProvider.notifier).resumePolling();
        ref.read(printerStatusesProvider.notifier).resume();
        ref.read(smartPlugsProvider.notifier).resumePolling();
        ref.read(tokenRefresherProvider)?.start();
      },
    );
    // After first render: one-time notification onboarding (permission +
    // request to allow "Unrestricted" battery usage).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOnboardNotifications();
    });
  }

  Future<void> _maybeOnboardNotifications() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_onboardingFlag) ?? false) return;
    await prefs.setBool(_onboardingFlag, true);
    await _runNotificationOnboarding();
  }

  /// Requests notification permission, and if app is not exempt from battery
  /// optimization — shows a dialog with link to settings.
  ///
  /// `manual` = triggered by button (not auto-onboarding): then on "quiet"
  /// paths (permission denied / already set up) show SnackBar
  /// so button doesn't look dead.
  Future<void> _runNotificationOnboarding({bool manual = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final granted =
        await ref.read(notificationServiceProvider).requestPermission();
    if (!mounted) return;
    if (!granted) {
      if (manual) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.notificationsBlocked)),
        );
      }
      return;
    }
    final battery = BatteryOptimization();
    if (await battery.isIgnoring()) {
      if (manual && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.notificationsReady)),
        );
      }
      return;
    }
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.batteryOptTitle),
        content: Text(l10n.batteryOptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.batteryOptLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.batteryOptAllow),
          ),
        ],
      ),
    );
    if (open ?? false) await battery.request();
  }

  /// Notification menu: background monitoring toggle + re-onboard
  /// (permission/battery). Opened from bell icon.
  void _openNotificationMenu(BuildContext context, AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer(
              builder: (ctx, ref, _) {
                final enabled = ref.watch(bgMonitoringEnabledProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.sync),
                  title: Text(l10n.bgMonitoringToggle),
                  subtitle: Text(l10n.bgMonitoringSubtitle),
                  value: enabled,
                  onChanged: (v) => _setBgMonitoring(sheetCtx, ref, l10n, v),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l10n.notifEventsMenu),
              onTap: () {
                Navigator.pop(sheetCtx);
                context.push('/settings/notifications');
              },
            ),
            ListTile(
              leading: const Icon(Icons.battery_saver),
              title: Text(l10n.batteryOptMenu),
              onTap: () {
                Navigator.pop(sheetCtx);
                _runNotificationOnboarding(manual: true);
              },
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
    messenger.showSnackBar(
      SnackBar(
        content: Text(enabled ? l10n.bgMonitoringOn : l10n.bgMonitoringOff),
      ),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.sessionExpired)),
        );
        context.go('/setup');
      }
    });

    final state = ref.watch(dashboardProvider);
    final profile = ref.watch(serverProfileProvider);
    final statuses = ref.watch(printerStatusesProvider);
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull;
    final t = DashTokens.of(context);

    // Keep proactive JWT refresh alive while dashboard is on screen,
    // and start it (idempotently). Lifecycle pauses/resumes it.
    ref.watch(tokenRefresherProvider)?.start();

    // Full-screen dark/light gradient backdrop behind a transparent Scaffold —
    // gives the seamless "designed screen" look through the app bar.
    return Container(
      decoration: BoxDecoration(gradient: t.backgroundGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: _AppDrawer(profileLabel: profile?.label),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            l10n.printersTitle,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: t.textPrimary,
            ),
          ),
          iconTheme: IconThemeData(color: t.textPrimary),
          actions: [
            const Center(child: ConnectionModeChip()),
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.batteryOptMenu,
              color: t.textPrimary,
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => _openNotificationMenu(context, l10n),
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
                      style: TextStyle(
                        fontFamily: DashTokens.fontMono,
                        fontSize: 11.5,
                        color: t.textTertiary,
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
            Expanded(child: _body(context, state, statuses, l10n)),
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
    AppLocalizations l10n,
  ) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
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
              Text(state.error?.localized(l10n) ?? l10n.connectFailed,
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(dashboardProvider.notifier).refresh(),
                child: Text(l10n.retry),
              ),
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
    final filtered = q.isEmpty
        ? printers
        : printers
            .where((p) => p.printer.name.toLowerCase().contains(q))
            .toList();

    return Column(
      children: [
        _SummaryHeader(printers: printers),
        // Search bar only makes sense with multiple printers.
        if (printers.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SearchBar(
              hintText: l10n.searchPrinters,
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
            ),
          )
        else
          const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            printers.isEmpty
                                ? l10n.noPrinters
                                : l10n.noSearchResults(_query),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => PrinterCard(
                      key: ValueKey(filtered[i].printer.id),
                      item: filtered[i],
                    ),
                  ),
          ),
        ),
      ],
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
                                  style: TextStyle(
                                    fontFamily: DashTokens.fontUi,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                    color: t.textPrimary,
                                  ),
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
                ),
                _DrawerTile(
                  icon: Icons.travel_explore_rounded,
                  label: l10n.makerworldMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/makerworld');
                  },
                ),
                _DrawerTile(
                  icon: Icons.qr_code_2_rounded,
                  label: l10n.swatchCodesMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/swatches');
                  },
                ),
                _DrawerTile(
                  icon: Icons.folder_special_outlined,
                  label: l10n.projectsMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/projects');
                  },
                ),
                _DrawerTile(
                  icon: Icons.bar_chart_rounded,
                  label: l10n.menuStatistics,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/stats');
                  },
                ),
                _DrawerTile(
                  icon: Icons.tune_rounded,
                  label: l10n.notifEventsMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/settings/notifications');
                  },
                ),
                const Divider(indent: 16, endIndent: 16, height: 16),
                _DrawerTile(
                  icon: Icons.cloud_outlined,
                  label: l10n.cloudAccountMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/settings/cloud');
                  },
                ),
                _DrawerTile(
                  icon: Icons.swap_horiz_rounded,
                  label: l10n.changeServer,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmChangeServer(context, ref, l10n);
                  },
                ),
                _DrawerTile(
                  icon: Icons.info_outline_rounded,
                  label: l10n.aboutMenu,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/about');
                  },
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
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 12,
                        color: t.textTertiary,
                      ),
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
      BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    // Read the notifier up front: the caller pops the drawer before calling us,
    // so this `_AppDrawer` (a ConsumerWidget) is disposed during the dialog
    // await — touching `ref` afterwards throws "Cannot use ref after dispose".
    final profiles = ref.read(serverProfileProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.changeServerQuestion),
        content: Text(l10n.changeServerWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.change),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
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
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.textSecondary,
              ),
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
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
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: t.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Summary at top of list: how many printers are working and which
/// will be free soonest (least remaining time).
class _SummaryHeader extends ConsumerWidget {
  const _SummaryHeader({required this.printers});

  final List<PrinterWithStatus> printers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    // Total power across farm from smart plugs (separate polling lane).
    final hasPlugs = ref.watch(smartPlugsProvider.select((s) => s.hasAnyPlug));
    final totalPowerW =
        ref.watch(smartPlugsProvider.select((s) => s.totalPowerW));
    final active = printers
        .where((p) =>
            (p.status?.connected ?? false) && (p.status?.isPrinting ?? false))
        .toList()
      ..sort((a, b) => (a.status!.remainingTime ?? 1 << 30)
          .compareTo(b.status!.remainingTime ?? 1 << 30));

    final next = active.isEmpty ? null : active.first;
    final dotColor = active.isEmpty ? t.textTertiary : t.accentGreen;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 8),
          Text(
            active.isEmpty
                ? l10n.noActivePrints
                : l10n.printingCount(active.length),
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active.isEmpty ? t.textSecondary : t.textPrimary,
            ),
          ),
          if (next != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: l10n.nextAvailableLabel),
                  TextSpan(
                    text: next.printer.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: _nextSuffix(l10n, next)),
                ]),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 12,
                  color: t.textSecondary,
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
                    style: TextStyle(
                      fontFamily: DashTokens.fontMono,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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
      if (r != null)
        r < 60
            ? l10n.durationMinutes(r)
            : l10n.durationHoursMinutes(r ~/ 60, r % 60),
    ];
    return parts.isEmpty ? '' : ' (${parts.join(' · ')})';
  }
}
