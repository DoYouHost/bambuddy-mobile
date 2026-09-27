import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// [raw] as a web address, or null when it is anything else.
///
/// Links the server stores were typed by some user of that server. Handed to
/// `launchUrl` as they are, an `intent:`, `market:` or custom-scheme link
/// starts whatever app on this phone claims it, so only an http(s) address
/// with a host may leave the app.
Uri? webLinkOrNull(String? raw) {
  final uri = Uri.tryParse(raw?.trim() ?? '');
  if (uri == null || uri.host.isEmpty) return null;
  return uri.isScheme('http') || uri.isScheme('https') ? uri : null;
}

/// Opens [url] in the browser, and says so when it could not — refused by
/// [webLinkOrNull], or no app on the phone takes a web link. Every link the
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
