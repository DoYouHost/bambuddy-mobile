import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// What the reader is told about the connected server's version. A read that
/// threw and a server that answered no version are one fact to the reader: no
/// footer is the place to sort the causes out.
String serverVersionText(AppLocalizations l10n, AsyncValue<String?> version) {
  // `valueOrNull` before the state: a refresh and a failed refresh both arrive
  // carrying the previous value, which matching on the state first would blank.
  final known = version.valueOrNull?.trim();
  if (known != null && known.isNotEmpty) return l10n.serverVersionLabel(known);
  if (version.isLoading) return l10n.serverVersionLabel('…');
  return l10n.serverVersionUnknown;
}
