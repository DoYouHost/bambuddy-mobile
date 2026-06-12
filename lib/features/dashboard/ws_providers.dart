import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/ws_client.dart';
import '../../core/auth/credentials_store.dart';
import '../../core/models/printer_status.dart';
import '../../core/settings/server_profile.dart';
import '../../providers.dart';

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
  final client = WsClient(
    url: wsUrlFor(profile.baseUrl),
    authHeaders: () => wsAuthHeaders(profile.authMode, creds),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Najnowszy status per drukarka z WS (`Map<printerId, PrinterStatus>`).
/// Dashboard nakłada to na listę z pollingu — WS jest źródłem świeżości,
/// REST źródłem składu drukarek (WS nie wysyła listy, tylko statusy).
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
      state = {...state, status.id: status};
    });
    ref.onDispose(sub.cancel);
    client.start();
    return const {};
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
