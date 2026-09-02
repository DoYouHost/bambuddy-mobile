import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../providers.dart';

/// The plate-clear gate, in one place for the three surfaces that read it: the
/// phone's printer card, the watch's control screen, and the queue's
/// acknowledgement before a manual start. Two halves have to agree — the
/// scheduler requiring it (`require_plate_clear`, a server setting) and this
/// printer's plate still being flagged dirty (`awaiting_plate_clear`) — and
/// each call site used to spell that out in its own `?? false` / `!= true`
/// dialect.

/// Whether this server releases the plate-clear gate on a printer it cannot
/// reach (server #2864).
///
/// Not a `ServerFeature` row, because a version cannot answer it: the change
/// landed inside the 1.2.6 beta cycle, where every daily build reports the same
/// `1.2.6b1`. No response reveals it either — the flag is reported the same way
/// before and after — so the app offers the control and takes the server's own
/// refusal as the answer. `true` until a `POST /printers/{id}/clear-plate`
/// comes back with the pre-#2864 "Printer not connected", after which the
/// offline control stops being offered for the rest of the session.
final offlinePlateClearProvider =
    NotifierProvider<OfflinePlateClearNotifier, bool>(
  OfflinePlateClearNotifier.new,
);

class OfflinePlateClearNotifier extends Notifier<bool> {
  @override
  bool build() {
    // A different server answers differently, so the observation must not
    // travel with the user to the next profile.
    ref.watch(serverProfileProvider);
    return true;
  }

  void observeRefusal() => state = false;
}

/// Whether nothing queued for this printer can start until its plate is
/// acknowledged.
///
/// [gateEnabled] is the server's `require_plate_clear`, passed as a callback
/// because the two doors reach it differently — a screen watches it, the
/// queue's pre-start check awaits it — and because it must only be reached when
/// it can matter: the per-printer half is false on almost every card, and
/// reading the setting anyway subscribes each of them to the server-settings
/// fetch behind it.
bool plateClearPending(
  PrinterStatus? status, {
  required bool Function() gateEnabled,
}) =>
    status?.awaitingPlateClear == true && gateEnabled();

/// Whether a screen should offer the acknowledgement for [status].
///
/// Watches both halves, so the control appears and withdraws on its own. An
/// unreachable printer is offered it too — the gate is bambuddy's own flag and
/// releasing it sends nothing to the machine, while under Auto Power Off "plate
/// dirty, printer off" is how every print ends. The exception is a server that
/// has already refused that (see [offlinePlateClearProvider]), where the button
/// would be dead.
bool plateClearOffered(WidgetRef ref, PrinterStatus? status) {
  final pending = plateClearPending(
    status,
    gateEnabled: () =>
        ref.watch(requirePlateClearProvider).valueOrNull ?? false,
  );
  if (!pending) return false;
  return status?.connected == true || ref.watch(offlinePlateClearProvider);
}

/// Whether [serverSaid] is a pre-#2864 server insisting on reaching the printer
/// before it will release the gate.
///
/// Takes the server's words rather than an exception because the two transports
/// keep different halves of one: the phone has the status code and the detail,
/// while the watch's relay forwards the detail alone. The words are enough —
/// the current server has no such refusal on this route at all, and its only
/// other
/// 400 there says "not awaiting plate-clear acknowledgment", so a reworded
/// message degrades to the generic failure rather than to a wrong explanation.
/// Matching on wording follows `AppApiException.isApiKeyOwnerDisabled`.
bool isOfflinePlateClearRefusal(String? serverSaid) =>
    serverSaid != null && serverSaid.toLowerCase().contains('not connected');

/// Records a plate-clear failure that turned out to be that refusal, so the
/// offline control stops being offered, and says whether it was one.
///
/// Each surface words it for the room it has — a sentence in a snack bar on the
/// phone, a short line in a toast on the watch — so this hands back the
/// classification rather than the message.
///
/// Takes the notifier rather than a `WidgetRef` on purpose: this is only ever
/// called after the request came back, and by then the control that sent it may
/// be gone — a card whose printer reconnected, a screen the user left. `ref`
/// throws once its widget is disposed (`Cannot use "ref" after the widget was
/// disposed`), so the latch is read out **before** the request goes out, next to
/// the messenger, and it outlives the widget either way.
bool recordPlateClearRefusal(
  OfflinePlateClearNotifier gate,
  String? serverSaid,
) {
  if (!isOfflinePlateClearRefusal(serverSaid)) return false;
  gate.observeRefusal();
  return true;
}
