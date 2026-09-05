import '../../core/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/server_refusal.dart';

/// What to tell the user when the server refused to start a slice.
///
/// The status names none of the three reasons; only the server's English
/// `detail` does. [serverRefusal] is the ladder every feature shares.
String sliceRefusalMessage(AppLocalizations l10n, AppApiException error) =>
    serverRefusal(l10n, error, _rules);

final _rules = <RefusalRule>[
  // Before the STEP rule, and that order is the whole point: the archive
  // route's format refusal is "must be STL, 3MF, or STEP", which names the
  // format without being about it.
  (['must be stl'], (l10n) => l10n.sliceRefusedFormat),
  (['step'], (l10n) => l10n.sliceRefusedStep),
  (['no source file'], (l10n) => l10n.sliceRefusedNoSource),
];
