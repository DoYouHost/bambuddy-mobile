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

/// Whether the plate-clear control belongs on this screen, and whether it can
/// be pressed yet.
///
/// Reads `awaitingPlateClear` before it watches anything: a card whose plate is
/// clean must not subscribe every printer on the dashboard to the settings
/// fetch, which is the same reason [plateClearPending] takes a callback.
ControlOffer plateClearOffer(WidgetRef ref, PrinterStatus? status) {
  if (status?.awaitingPlateClear != true) return ControlOffer.hidden;
  final offer = controlOffer([() => ref.watch(requirePlateClearProvider)]);
  if (offer == ControlOffer.hidden) return ControlOffer.hidden;
  if (status?.connected != true && !ref.watch(offlinePlateClearProvider)) {
    return ControlOffer.hidden;
  }
  return offer;
}

/// [plateClearOffer] for a caller with no disabled state to render — the watch,
/// whose action list is built from plain callbacks.
bool plateClearOffered(WidgetRef ref, PrinterStatus? status) =>
    plateClearOffer(ref, status) == ControlOffer.offered;

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
