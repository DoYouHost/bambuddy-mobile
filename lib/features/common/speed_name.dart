import '../../l10n/app_localizations.dart';

/// The localized name of a print speed level (1 silent to 4 ludicrous); null
/// for any other level, so each caller picks its own fallback.
String? speedName(AppLocalizations l10n, int? level) => switch (level) {
  1 => l10n.speedSilent,
  2 => l10n.speedStandard,
  3 => l10n.speedSport,
  4 => l10n.speedLudicrous,
  _ => null,
};
