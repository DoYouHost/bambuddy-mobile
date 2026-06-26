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
import 'widgets/connection_banner.dart';
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
    // Cykl życia (Model A: serwis tła przejmuje na czas tła).
    // - Tło: jeśli monitoring w tle włączony, startujemy foreground service —
    //   jego osobny isolate jest JEDYNYM właścicielem powiadomień i ma własny
    //   WS (łapie też START wydruku w tle). UI wycisza się całkowicie: zwalnia
    //   socket i zatrzymuje polling (FGS trzyma proces, więc timer dalej by
    //   tykał i bił po serwerze bez potrzeby).
    // - Powrót: zatrzymujemy serwis, backfill REST, reconnect WS UI.
    _lifecycle = AppLifecycleListener(
      onPause: () {
        if (ref.read(bgMonitoringEnabledProvider)) {
          ref.read(backgroundMonitorProvider).start();
        }
        ref.read(printerStatusesProvider.notifier).suspend();
        ref.read(dashboardProvider.notifier).pausePolling();
        ref.read(smartPlugsProvider.notifier).pausePolling();
        // Odnowę tokenu w tle przejmuje isolate FGS — UI milczy.
        ref.read(tokenRefresherProvider)?.stop();
      },
      onResume: () {
        ref.read(backgroundMonitorProvider).stop();
        ref.read(dashboardProvider.notifier).resumePolling();
        ref.read(printerStatusesProvider.notifier).resume();
        ref.read(smartPlugsProvider.notifier).resumePolling();
        ref.read(tokenRefresherProvider)?.start();
      },
    );
    // Po pierwszym renderze: jednorazowy onboarding powiadomień (uprawnienie +
    // prośba o „Bez ograniczeń" dla baterii).
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

  /// Prosi o uprawnienie powiadomień, a jeśli apka nie jest zwolniona z
  /// optymalizacji baterii — pokazuje dialog z linkiem do ustawień.
  ///
  /// `manual` = wywołane przyciskiem (nie auto-onboardingiem): wtedy na „cichych"
  /// ścieżkach (uprawnienie odrzucone / wszystko już ustawione) dajemy SnackBar,
  /// żeby przycisk nie wyglądał na martwy.
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

  /// Menu powiadomień: przełącznik monitoringu w tle + ponowny onboarding
  /// (uprawnienie/bateria). Otwierane spod ikony dzwonka.
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
    // Wyłączenie ma działać od razu, gdyby serwis akurat chodził; włączenie
    // zadziała przy najbliższym przejściu w tło (na pierwszym planie FGS nie
    // jest nam potrzebny).
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

    // Wygaśnięcie sesji → łagodny powrót do konfiguracji,
    // nigdy crash ani martwy dashboard.
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

    // Utrzymujemy proaktywną odnowę JWT żywą, dopóki dashboard jest na ekranie,
    // i uruchamiamy ją (idempotentnie). Cykl życia ją wstrzymuje/wznawia.
    ref.watch(tokenRefresherProvider)?.start();

    return Scaffold(
      drawer: _AppDrawer(profileLabel: profile?.label),
      appBar: AppBar(
        title: Text(l10n.printersTitle),
        actions: [
          IconButton(
            tooltip: l10n.batteryOptMenu,
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () => _openNotificationMenu(context, l10n),
          ),
        ],
        // Tylko przyjazna etykieta profilu (jeśli ustawiona) — bez adresu URL.
        bottom: profile?.label == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    profile!.label!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          if (state.stale)
            ConnectionBanner(message: l10n.serverUnreachableStale)
          // WS wznawia połączenie, ale polling wciąż daje aktualne dane —
          // baner informacyjny, nie alarmowy. Nie dublujemy banera „stale".
          else if (_wsReconnecting(wsState))
            ConnectionBanner(
              message: l10n.wsReconnecting,
              tone: BannerTone.info,
            ),
          Expanded(child: _body(context, state, statuses, l10n)),
        ],
      ),
    );
  }

  /// Baner WS pokazujemy, gdy aktywnie próbujemy odzyskać połączenie —
  /// nie przy `connected` (cisza) ani `suspended` (apka w tle).
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

    // Pierwsze ładowanie padło — nie ma czego pokazać poza błędem.
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

    // Skład drukarek bierzemy z pollingu (roster), a status nakładamy ze
    // wspólnej mapy statusów (WS + poll scalone w printerStatusesProvider).
    // Brak wpisu w mapie → zostaje status z samej listy.
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
        // Wyszukiwarka ma sens dopiero przy wielu drukarkach.
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

/// Szuflada nawigacyjna z ekranami „app-level" (drugorzędnymi względem zakładek
/// dolnej belki): Statystyki, Powiadomienia, zmiana serwera. Hamburger pokazuje
/// się automatycznie w AppBarze Dashboardu, bo Scaffold ma ustawioną `drawer`.
class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({this.profileLabel});

  final String? profileLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brandowany nagłówek: ikona aplikacji w uniesionym kafelku + nazwa
          // + profil, na gradiencie z miękką poświatą w narożniku (zamiast
          // pustego prostokąta DrawerHeader).
          ClipRect(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.18),
                      scheme.primaryContainer,
                    ),
                    scheme.primaryContainer.withValues(alpha: 0.45),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Poświata — okrąg primary rozmyty w prawym górnym rogu.
                  Positioned(
                    top: -48,
                    right: -36,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: 0.22),
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
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.30),
                                width: 1,
                              ),
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
                                  'BamBuddy',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                    color: scheme.onPrimaryContainer,
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
          // Stopka z wersją — czytana z metadanych pakietu (jak na ekranie „O…").
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.print_rounded,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) => Text(
                      snap.hasData
                          ? 'BamBuddy v${snap.data!.version}+${snap.data!.buildNumber}'
                          : 'BamBuddy',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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

  /// Powtórka potwierdzenia zmiany serwera — wyczyszczenie profilu odsyła do
  /// `/setup` przez router. Trzymane przy szufladzie, by nie zależeć od metod
  /// stanu Dashboardu.
  Future<void> _confirmChangeServer(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
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
      await ref.read(serverProfileProvider.notifier).clear();
    }
  }
}

/// Etykieta profilu (adres serwera) jako delikatny „chip" pod nazwą aplikacji.
/// Gdy brak profilu — chowamy się, by nie zostawiać pustego miejsca.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.onPrimaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_rounded,
              size: 13,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pozycja szuflady w stylu M3 — zaokrąglony „pigułkowy" kształt z ripple,
/// tintowany kafelek ikony i chevron sugerujący nawigację. Opcjonalny `tint`
/// pozwala wyróżnić pozycję (np. zmiana serwera). Wydzielone, by lista była
/// zwięzła.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 21, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Podsumowanie u góry listy: ile drukarek pracuje i która zwolni się
/// najwcześniej (najmniej pozostałego czasu).
class _SummaryHeader extends ConsumerWidget {
  const _SummaryHeader({required this.printers});

  final List<PrinterWithStatus> printers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    // Suma mocy całej farmy ze smart gniazdek (osobny tor pollingu).
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active.isEmpty ? theme.disabledColor : scheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            active.isEmpty
                ? l10n.noActivePrints
                : l10n.printingCount(active.length),
            style: theme.textTheme.bodyMedium,
          ),
          if (next != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: l10n.nextAvailableLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: next.printer.name,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: _nextSuffix(l10n, next),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (hasPlugs) ...[
            // Gdy jest „następna wolna" drukarka, jej Flexible zjada miejsce —
            // wtedy bez Spacera; inaczej dosuwamy moc do prawej krawędzi.
            if (next == null) const Spacer() else const SizedBox(width: 12),
            Tooltip(
              message: l10n.totalPowerTooltip,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(
                    l10n.powerWatts(totalPowerW.round()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
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
