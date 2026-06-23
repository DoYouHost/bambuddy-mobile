import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/ws_client.dart';
import '../../core/auth/credentials_store.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/settings/server_profile.dart';
import '../../core/widget/home_widget_publisher.dart';
import '../../core/widget/widget_cover_cache.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';
import '../notifications/print_monitor.dart' show systemAppLocalizations;

/// Buduje URL WS z baseUrl profilu: http→ws, https→wss, ścieżka `…/api/v1/ws`.
Uri wsUrlFor(String baseUrl) {
  final u = Uri.parse(baseUrl);
  final scheme = u.scheme == 'https' ? 'wss' : 'ws';
  return u.replace(scheme: scheme, path: '${u.path}${Endpoints.apiPrefix}/ws');
}

/// Nagłówki auth dla handshake'u WS — branchują po [AuthMode] tak samo jak
/// interceptor REST. WS bambuddy uwierzytelnia się nagłówkiem (nie tokenem
/// w query — patrz pamięć ws-contract-m2), więc reconnect z odświeżonym
/// kluczem/JWT wystarcza, bez osobnego mintowania.
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

/// Pojedynczy [WsClient] dla aktywnego profilu. Przebudowywany przy zmianie
/// profilu (stary klient jest wtedy zamykany). Rzuca bez profilu — trasy bez
/// profilu i tak idą do /setup.
final wsClientProvider = Provider<WsClient>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null) {
    throw StateError('wsClientProvider użyty bez profilu serwera');
  }
  final creds = ref.watch(credentialsStoreProvider);
  final auth = ref.watch(authServiceProvider);
  final client = WsClient(
    url: wsUrlFor(profile.baseUrl),
    authHeaders: () => wsAuthHeaders(profile.authMode, creds),
    // Tylko JWT da się odświeżyć cichym re-loginem; klucz API jest stały,
    // a serwer bez auth nie odrzuca. silentReLogin zapisuje świeży JWT,
    // który authHeaders odczyta przy ponownym połączeniu.
    refreshAuth: profile.authMode == AuthMode.jwt
        ? () async => await auth.silentReLogin(profile.baseUrl) != null
        : null,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Najnowszy status per drukarka (`Map<printerId, PrinterStatus>`) — jedno
/// wspólne źródło prawdy dla UI i [PrintMonitor]. Zasilane z DWÓCH torów:
/// strumienia WS (świeżość w czasie rzeczywistym) oraz pollingu REST
/// (fallback gdy WS padnie, backfill po wznowieniu). Polling wpina wyniki
/// przez [PrinterStatusesNotifier.ingestPoll]; składem drukarek (rosterem)
/// nadal zarządza `dashboardProvider` — WS listy nie wysyła.
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
      // Scalamy na poprzednim stanie, by ramka WS nie skasowała pól, których
      // WS nie niesie (np. tryb komory `airduct_mode` z REST) — patrz mergedWith.
      state = {...state, status.id: status.mergedWith(state[status.id])};
      _publishWidget();
    });
    ref.onDispose(sub.cancel);
    client.start();
    return const {};
  }

  /// Odświeża natywny widget ekranu głównego stanem wybranej drukarki. Wołane
  /// po każdej zmianie [state] (WS i poll). Lokalizacja z systemu — apka i tak
  /// idzie za ustawieniem systemu. Błąd publikacji nie może wywrócić strumienia.
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

  /// Pobiera okładkę bieżącego wydruku do pliku (auth tokenem kamery). Goły Dio
  /// + token z [cameraTokenServiceProvider]; cache po `cover_url` w [WidgetCoverCache].
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

  /// Scala statusy z pollingu REST do tej samej mapy co WS — by `PrintMonitor`
  /// i UI miały jedno źródło prawdy niezależnie od tego, czy WS żyje. Wpisy
  /// `null` (status endpoint padł) pomijamy, żeby nie skasować świeższego
  /// statusu z WS. Last-write-wins jest bezpieczny: poll zwraca BIEŻĄCY stan
  /// serwera (nie stary job), więc nie generuje fałszywych zboczy w monitorze,
  /// a alerty mają stałe id per drukarka, więc duplikat z dwóch torów się
  /// nadpisuje, nie dubluje.
  void ingestPoll(List<PrinterWithStatus> polled) {
    // Poll niesie pełny roster, więc to autorytatywne źródło składu — przycinamy
    // statusy drukarek, które zniknęły z listy (inaczej rosłyby bez końca; WS
    // sam nie raportuje usunięć). Wpisy z null-statusem zostają w rosterze.
    final rosterIds = {for (final p in polled) p.printer.id};
    final next = {...state}..removeWhere((id, _) => !rosterIds.contains(id));
    var changed = next.length != state.length;
    for (final p in polled) {
      final s = p.status;
      if (s == null) continue;
      // Scalamy na bieżącym stanie (mógł pochodzić z WS), by poll nie skasował
      // pól, których REST nie niesie (model/vt_tray/cover_url…) — patrz mergedWith.
      next[p.printer.id] = s.mergedWith(next[p.printer.id]);
      changed = true;
    }
    if (changed) {
      state = next;
      _publishWidget();
    }
  }

  /// Wołane przez lifecycle: tło → zamknij socket.
  void suspend() {
    final profile = ref.read(serverProfileProvider);
    if (profile == null) return;
    ref.read(wsClientProvider).suspend();
  }

  /// Powrót z tła → wznów socket (backfill REST robi dashboardProvider).
  void resume() {
    final profile = ref.read(serverProfileProvider);
    if (profile == null) return;
    ref.read(wsClientProvider).resume();
  }
}

/// Stan połączenia WS dla banera. `null` (brak danych) traktujemy w UI jak
/// „jeszcze nie wiadomo" — baner pokazujemy tylko dla stanów nie-connected.
final wsConnectionStateProvider = StreamProvider<WsConnectionState>((ref) {
  final profile = ref.watch(serverProfileProvider);
  if (profile == null) return const Stream.empty();
  return ref.watch(wsClientProvider).connectionStates;
});
