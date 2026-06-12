import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/ws_client.dart';
import '../../core/models/printer_status.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import 'providers.dart';
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

  @override
  void initState() {
    super.initState();
    // Cykl życia WS wg §3 planu: w tle zamykamy socket (bez FGS na Androidzie),
    // przy powrocie najpierw backfill REST (natychmiastowa świeżość), potem
    // reconnect WS. WS żyje tylko, gdy dashboard jest zamontowany.
    _lifecycle = AppLifecycleListener(
      onPause: () => ref.read(printerStatusesProvider.notifier).suspend(),
      onResume: () {
        ref.read(dashboardProvider.notifier).refresh();
        ref.read(printerStatusesProvider.notifier).resume();
      },
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
    final wsStatuses = ref.watch(printerStatusesProvider);
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.printersTitle),
        actions: [
          IconButton(
            tooltip: l10n.changeServer,
            icon: const Icon(Icons.settings),
            onPressed: () => _confirmChangeServer(context, ref, l10n),
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
          Expanded(child: _body(context, state, wsStatuses, l10n)),
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
    Map<int, PrinterStatus> wsStatuses,
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

    // Nakładamy świeży status z WS na listę z pollingu (REST daje skład
    // drukarek, WS — aktualność). Brak wpisu WS → zostaje status z pollingu.
    final printers = [
      for (final p in state.printers!)
        wsStatuses.containsKey(p.printer.id)
            ? PrinterWithStatus(
                printer: p.printer,
                status: wsStatuses[p.printer.id],
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

/// Podsumowanie u góry listy: ile drukarek pracuje i która zwolni się
/// najwcześniej (najmniej pozostałego czasu).
class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.printers});

  final List<PrinterWithStatus> printers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final active = printers.where((p) => p.status?.isPrinting ?? false).toList()
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
