import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/ws_client.dart';
import '../../core/api/ws_token.dart';
import '../../core/auth/credentials_store.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/settings/server_profile.dart';
import '../../core/widget/home_widget_publisher.dart';
import '../../core/widget/widget_cover_cache.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';
import '../maintenance/maintenance_providers.dart';
import '../notifications/print_monitor.dart' show systemAppLocalizations;
import '../queue/queue_providers.dart';

/// Builds WS URL from profile baseUrl: http→ws, https→wss, path `…/api/v1/ws`.
Uri wsUrlFor(String baseUrl) {
  final u = Uri.parse(baseUrl);
  final scheme = u.scheme == 'https' ? 'wss' : 'ws';
  return u.replace(scheme: scheme, path: '${u.path}${Endpoints.apiPrefix}/ws');
}

/// Auth headers for WS handshake — branches by [AuthMode] same as REST
/// interceptor. Newer servers (GHSA-r2qv follow-up) instead require a `?token=`
/// minted via [WsTokenService]; we still send headers so older header-only
/// servers keep working. See [wsClientProvider].
Future<Map<String, String>> wsAuthHeaders(
  AuthMode mode,
  CredentialsStore creds,
) async {
  switch (mode) {
    case AuthMode.none:
      return const {};
    case AuthMode.jwt:
      final jwt = await creds.readJwt();
      return jwt == null ? const {} : {'Authorization': 'Bearer $jwt'};
    case AuthMode.apiKey:
      final key = await creds.readApiKey();
      return key == null ? const {} : {'X-API-Key': key};
  }
}

/// Mints the WS handshake token for the active profile (see [WsTokenService]).
/// Uses the authenticated Dio so the mint itself carries header/JWT auth.
final wsTokenServiceProvider = Provider<WsTokenService>(
  (ref) => WsTokenService(ref.watch(apiClientProvider).dio),
);

/// Single [WsClient] for active profile. Rebuilt on profile change (old client
/// then closed). Throws without profile — routes without profile go to /setup anyway.
final wsClientProvider = Provider<WsClient>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null) {
    throw StateError('wsClientProvider used without server profile');
  }
  final creds = ref.watch(credentialsStoreProvider);
  final auth = ref.watch(authServiceProvider);
  final wsToken = ref.watch(wsTokenServiceProvider);
  final client = WsClient(
    url: wsUrlFor(profile.baseUrl),
    authHeaders: () => wsAuthHeaders(profile.authMode, creds),
    // `?token=` for the handshake (new server); null → header-only fallback.
    queryToken: wsToken.token,
    invalidateQueryToken: wsToken.invalidate,
    // Only JWT can refresh via silent re-login; API key is static,
    // server without auth doesn't reject. silentReLogin saves fresh JWT,
    // which authHeaders reads on reconnect.
    refreshAuth: profile.authMode == AuthMode.jwt
        ? () async => await auth.silentReLogin(profile.baseUrl) != null
        : null,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Latest status per printer (`Map<printerId, PrinterStatus>`) — one
/// shared source of truth for UI and [PrintMonitor]. Fed from TWO lanes:
/// WS stream (real-time freshness) and REST polling (fallback if WS fails,
/// backfill on resume). Polling hooks results via [PrinterStatusesNotifier.ingestPoll];
/// printer roster still managed by `dashboardProvider` — WS doesn't send list.
final printerStatusesProvider =
    NotifierProvider<PrinterStatusesNotifier, Map<int, PrinterStatus>>(
  PrinterStatusesNotifier.new,
);

class PrinterStatusesNotifier extends Notifier<Map<int, PrinterStatus>> {
  @override
  Map<int, PrinterStatus> build() {
    final profile = ref.watch(serverProfileProvider);
    if (profile == null) return const {};

    final client = ref.watch(wsClientProvider);
    final sub = client.statuses.listen((status) {
      // Merge on previous state so WS frame doesn't erase fields WS doesn't
      // carry (e.g. chamber mode `airduct_mode` from REST) — see mergedWith.
      final prev = state[status.id];
      final merged = status.mergedWith(prev);
      state = {...state, status.id: merged};
      _publishWidget();
      // Fallback trigger: a print just ended (active → not active). Queue
      // advances and maintenance counters tick at that moment, but the server
      // pushes neither over WS — refresh both so the tabs/badges stay live.
      if (prev?.isPrinting == true && !merged.isPrinting) {
        _scheduleQueueMaintenanceRefresh();
      }
    });
    ref.onDispose(sub.cancel);

    // Primary trigger: explicit print_start/print_complete frames.
    final printSub = client.printEvents.listen(
      (_) => _scheduleQueueMaintenanceRefresh(),
    );
    ref.onDispose(printSub.cancel);
    ref.onDispose(() => _refreshDebounce?.cancel());

    client.start();
    return const {};
  }

  Timer? _refreshDebounce;

  /// Coalesce bursts (e.g. print_complete frame + the status transition that
  /// follows it) into a single refresh. Providers are kept alive by the nav
  /// badge, and `refresh()` keeps the previous value so open screens don't
  /// flash a spinner.
  void _scheduleQueueMaintenanceRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(ref.read(queueProvider.notifier).refresh());
      unawaited(ref.read(maintenanceOverviewProvider.notifier).refresh());
    });
  }

  /// Refresh native home screen widget with state of selected printer. Called
  /// after each [state] change (WS and poll). Localization from system — app
  /// follows system setting anyway. Publish error can't break stream.
  void _publishWidget() {
    unawaited(
      HomeWidgetPublisher.publish(
        state,
        systemAppLocalizations(),
        describeHms: HmsCatalog.instance.describe,
        fetchCover: _fetchCover,
      ).catchError((_) {}),
    );
  }

  /// Fetch cover of current print to file (auth via camera token). Raw Dio
  /// + token from [cameraTokenServiceProvider]; cache by `cover_url` in [WidgetCoverCache].
  Future<String?> _fetchCover(PrinterStatus picked) {
    final profile = ref.read(serverProfileProvider);
    final cover = picked.coverUrl;
    if (profile == null || cover == null) return Future.value(null);
    final tokenSvc = ref.read(cameraTokenServiceProvider);
    return WidgetCoverCache.fetch(
      baseUrl: profile.baseUrl,
      coverPath: cover,
      dio: ref.read(bareDioProvider),
      token: ({bool forceRefresh = false}) =>
          tokenSvc.token(forceRefresh: forceRefresh),
    );
  }

  /// Merge REST poll statuses into same map as WS — so `PrintMonitor`
  /// and UI have single source of truth regardless of WS health. Skip `null`
  /// entries (status endpoint failed) to not erase fresher WS status.
  /// Last-write-wins is safe: poll returns CURRENT server state (not old job),
  /// so doesn't generate false edges in monitor, and alerts have fixed id per
  /// printer, so duplicate from two lanes overwrites, not duplicates.
  void ingestPoll(List<PrinterWithStatus> polled) {
    // Poll carries full roster, so authoritative source of composition — trim
    // statuses of printers gone from list (otherwise would grow unbounded; WS
    // doesn't report deletes). Entries with null-status stay in roster.
    final rosterIds = {for (final p in polled) p.printer.id};
    final next = {...state}..removeWhere((id, _) => !rosterIds.contains(id));
    var changed = next.length != state.length;
    for (final p in polled) {
      final s = p.status;
      if (s == null) continue;
      // Merge on current state (might come from WS) so poll doesn't erase
      // fields REST doesn't carry (model/vt_tray/cover_url…) — see mergedWith.
      next[p.printer.id] = s.mergedWith(next[p.printer.id]);
      changed = true;
    }
    if (changed) {
      state = next;
      _publishWidget();
    }
  }

  /// Called by lifecycle: background → close socket.
  void suspend() {
    final profile = ref.read(serverProfileProvider);
    if (profile == null) return;
    ref.read(wsClientProvider).suspend();
  }

  /// Return from background → resume socket (dashboardProvider does REST backfill).
  void resume() {
    final profile = ref.read(serverProfileProvider);
    if (profile == null) return;
    ref.read(wsClientProvider).resume();
  }
}

/// WS connection state for banner. `null` (no data) treated in UI like
/// "still unknown" — show banner only for non-connected states.
final wsConnectionStateProvider = StreamProvider<WsConnectionState>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null) return const Stream.empty();
  return ref.watch(wsClientProvider).connectionStates;
});
