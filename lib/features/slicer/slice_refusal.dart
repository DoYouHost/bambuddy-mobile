import '../../core/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';

/// What to tell the user when the server refused to start a slice.
///
/// The status names none of the three reasons; only the server's English
/// `detail` does. Known refusals are localized, an unknown one is quoted — a
/// phrasing we do not know yet still beats a generic failure — and no detail
/// falls back to the code. Mirrors `userWriteMessage`
/// (`features/admin/user_messages.dart`), which does this for the account rules.
String sliceRefusalMessage(AppLocalizations l10n, AppApiException error) {
  final detail = error.detail;
  if (detail == null || detail.trim().isEmpty) return error.localized(l10n);
  return _localizedRefusal(l10n, detail) ?? detail;
}

/// The server's own wording, matched loosely (`contains`, case-folded) so a
/// version that adds a filename or punctuation still lands.
String? _localizedRefusal(AppLocalizations l10n, String detail) {
  final d = detail.toLowerCase();
  // Before the STEP check, and that order is the whole point: the archive
  // route's format refusal is "must be STL, 3MF, or STEP", which names the
  // format without being about it.
  if (d.contains('must be stl')) return l10n.sliceRefusedFormat;
  if (d.contains('step')) return l10n.sliceRefusedStep;
  if (d.contains('no source file')) return l10n.sliceRefusedNoSource;
  return null;
}
