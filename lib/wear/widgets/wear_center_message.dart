import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'wear_scroll_view.dart';
import 'wear_settings_entry.dart';

/// What a watch screen shows instead of content it could not get: the reason,
/// a retry, and the way to the settings.
///
/// Shared because the second caller needed it and had nothing: a control screen
/// pushed from the picker outlives the home screen underneath, so when the poll
/// fails it is the one in front of the user — and it used to answer with
/// "printer unavailable", which reads as a printer that is gone rather than a
/// phone that cannot be reached, and offered no way to try again.
class WearCenterMessage extends StatelessWidget {
  const WearCenterMessage({
    super.key,
    required this.text,
    required this.onRetry,
  });

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => WearScrollView(
    // Short enough to sit in the middle of the face, but it scrolls when the
    // message wraps: on a 1.4" screen two lines of error plus two buttons is
    // already taller than the round-safe band.
    centerWhenShort: true,
    children: [
      Text(text, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: onRetry,
        child: Text(AppLocalizations.of(context).retry),
      ),
      // The reachable way out of a wrong server: a failed connection is
      // exactly when someone wants to change it, and retrying forever is
      // the only other thing this screen offers.
      const WearSettingsEntry(),
    ],
  );
}
