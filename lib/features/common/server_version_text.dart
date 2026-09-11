import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// What the reader is told about the connected server's version, from the three
/// states the read can be in. Shared by the phone's drawer footer and the
/// watch's settings footer, the same way `setupErrorText` is shared by the two
/// setup screens.
///
/// The decision worth keeping in one place is the last line: **a read that
/// threw and a server that answered no version are one fact to the reader**.
/// An older bambuddy has no `/updates/version` route, a phone too old for the
/// watch's RPC action stays silent, a server may be unreachable this second —
/// three different causes, one sentence, and no footer is the place to sort
/// them out.
String serverVersionText(AppLocalizations l10n, AsyncValue<String?> version) {
  // `valueOrNull` before the state, not a `switch` on the state: a refresh
  // arrives as `AsyncLoading` carrying the previous value, and an `AsyncError`
  // keeps it too. Matching on the state first would blank a version we still
  // know — and this one cannot go stale while it is displayed, because a
  // server changing version has restarted and dropped the connection.
  // Blank counts as not knowing: `Server ` with the answer missing off the end
  // is worse than saying so. Trimmed rather than merely non-empty, which is
  // the same contract `toStringOrNull` applies where these strings are read —
  // three screens hand this whatever they were given.
  final known = version.valueOrNull?.trim();
  if (known != null && known.isNotEmpty) return l10n.serverVersionLabel(known);
  // Nothing known yet and still asking: the label with an ellipsis rather than
  // "unknown", which would be a wrong answer for as long as the request is out.
  if (version.isLoading) return l10n.serverVersionLabel('…');
  return l10n.serverVersionUnknown;
}
