import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../providers.dart';
import 'dash_async.dart';

/// Whether this server releases the plate-clear gate on a printer it cannot
/// reach (server #2864). No version can answer it — the change landed mid-1.2.6
/// beta, where every build reports `1.2.6b1` — so the refusal is the answer.
final offlinePlateClearProvider =
    NotifierProvider<OfflinePlateClearNotifier, bool>(
      OfflinePlateClearNotifier.new,
    );

class OfflinePlateClearNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(serverProfileProvider);
    return true;
  }

  void observeRefusal() => state = false;
}

/// Whether nothing queued for this printer can start until its plate is
/// acknowledged. [gateEnabled] is a callback so that reading the server setting
/// does not subscribe every dashboard card to the fetch behind it.
bool plateClearPending(
  PrinterStatus? status, {
  required bool Function() gateEnabled,
}) => status?.awaitingPlateClear == true && gateEnabled();

/// Watches both halves, so the control appears and withdraws on its own.
bool plateClearOffered(WidgetRef ref, PrinterStatus? status) {
  final pending = plateClearPending(
    status,
    gateEnabled: () => ref.watch(requirePlateClearProvider).orFalse,
  );
  if (!pending) return false;
  return status?.connected == true || ref.watch(offlinePlateClearProvider);
}

/// The server's words rather than an exception: the phone has the status code
/// and the detail, the watch's relay forwards the detail alone. Follows
/// `AppApiException.isApiKeyOwnerDisabled`.
bool isOfflinePlateClearRefusal(String? serverSaid) =>
    serverSaid != null && serverSaid.toLowerCase().contains('not connected');

/// Takes the notifier, not a `WidgetRef`: this runs after the request came
/// back, by which time the control that sent it may be gone and `ref` throws.
/// Read the latch out before the request goes out, next to the messenger.
bool recordPlateClearRefusal(
  OfflinePlateClearNotifier gate,
  String? serverSaid,
) {
  if (!isOfflinePlateClearRefusal(serverSaid)) return false;
  gate.observeRefusal();
  return true;
}
