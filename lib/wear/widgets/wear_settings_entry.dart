import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../screens/wear_settings_screen.dart';

/// Way into [WearSettingsScreen], parked at the end of whatever the watch shows
/// first. It goes at the bottom of a scroll rather than into a corner of the
/// screen: a round face has no corner to spare, and settings are not what
/// anyone came to the watch for.
class WearSettingsEntry extends StatelessWidget {
  const WearSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const WearSettingsScreen()),
      ),
      icon: const Icon(Icons.settings_outlined, size: 14),
      label: Text(AppLocalizations.of(context).wearSettingsTitle),
    ),
  );
}
