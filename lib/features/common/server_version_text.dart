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
String serverVersionText(AppLocalizations l10n, AsyncValue<String?> version) =>
    switch (version) {
      AsyncData(:final value?) => l10n.serverVersionLabel(value),
      // Still asking: the label with an ellipsis rather than "unknown", which
      // would be a wrong answer for as long as the request is in flight.
      AsyncLoading() => l10n.serverVersionLabel('…'),
      _ => l10n.serverVersionUnknown,
    };
