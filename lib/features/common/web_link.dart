import 'package:flutter/material.dart';
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

/// Opens a server-supplied [url] in the browser, and says so when it could
/// not — refused by [webLinkOrNull] or by the platform.
Future<void> openWebLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final uri = webLinkOrNull(url);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) messenger.snack(l10n.linkOpenFailed);
}
