import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../providers.dart';

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

/// Whether [error] is a pre-#2864 server insisting on reaching the printer
/// before it will release the plate-clear gate.
///
/// Matched on the server's own wording, like
/// [AppApiException.isApiKeyOwnerDisabled]. It is safe to match loosely here:
/// the current server has no such refusal on this route at all, and its other
/// 400 says "not awaiting plate-clear acknowledgment" — so a reworded message
/// degrades to the generic failure rather than to a wrong explanation.
bool isOfflinePlateClearRefusal(AppApiException error) =>
    error.statusCode == 400 &&
    (error.detail?.toLowerCase().contains('not connected') ?? false);

/// Classifies a failed plate-clear acknowledgement, recording a pre-#2864
/// refusal so the offline control stops being offered.
///
/// Returns whether it was that refusal — the call site words it for the user
/// ("this server needs the printer online") instead of the generic failure.
bool recordPlateClearFailure(WidgetRef ref, AppApiException error) {
  if (!isOfflinePlateClearRefusal(error)) return false;
  ref.read(offlinePlateClearProvider.notifier).observeRefusal();
  return true;
}
