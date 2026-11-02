import 'package:app_util/app_util.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Opens [url] in the browser, and says so when it could not — refused by
/// `webLinkOrNull` (app_util), or no app on the phone takes a web link. Every link the
/// app opens goes through here, built-in ones too, so that answer is one.
Future<void> openWebLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final uri = webLinkOrNull(url);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      // ACTIVITY_NOT_FOUND: no browser installed or enabled.
    }
  }
  if (!opened) messenger.snack(l10n.linkOpenFailed);
}
