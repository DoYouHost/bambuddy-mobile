import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';

// App-wide settings and tools that belong to no feature: the demo account, the
// language outside the widget tree, the server-version line, the handles a
// flow keeps past its widget. A thing with a home of its own goes there.

/// Demo mode ("store review" mode): Play review needs full app access, and the
/// app only works against a self-hosted server, so a magic address serves a
/// fabricated dataset in-process (`DemoBackend`) and nothing leaves the device.
///
/// Reviewer instructions (Play Console → App access):
///   server address: `demo`, username: `demo`, password: `demo1234`.
abstract final class DemoConfig {
  /// Saved as the profile after a demo login. A single-label host never
  /// resolves publicly, so a request that escaped the interception would fail
  /// locally rather than reach anyone.
  static const baseUrl = 'http://demo';

  static const username = 'demo';
  static const password = 'demo1234';

  static bool isDemoUrl(String normalizedUrl) {
    final host = Uri.tryParse(normalizedUrl)?.host.toLowerCase();
    return host == 'demo' || host == 'demo.bambuddy.app';
  }
}

/// The app's language for code outside the widget tree — notifications, the
/// service isolate, the HMS catalogue — where there is no `BuildContext`.
Locale systemLocale() => resolveAppLocale(PlatformDispatcher.instance.locales);

/// `lookupAppLocalizations` throws on an unsupported language, so it is only
/// ever handed a resolved locale.
AppLocalizations systemAppLocalizations() =>
    lookupAppLocalizations(systemLocale());

/// The same resolution `MaterialApp` applies to `supportedLocales`, so text
/// built outside the tree speaks the language of the screen it opens.
Locale resolveAppLocale(List<Locale> preferred) =>
    basicLocaleListResolution(preferred, AppLocalizations.supportedLocales);

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

/// The two handles a flow keeps when it may outlive the widget that started it.
typedef DetachedHandles = ({
  ProviderContainer providers,
  ScaffoldMessengerState messenger,
});

/// Takes both **before the first `await`**, for a flow that can outlive its own
/// widget: afterwards `ref` throws and `ScaffoldMessenger.of(context)` has no
/// context to read, so the rows stay stale and the user is told nothing —
/// including that the action failed.
///
/// This is about the handles, not the widget: a `setState` after the await
/// still needs its own `mounted` check, and `showApiFailure` still wants
/// `mounted ? messenger : null` so a refusal nobody saw is recorded as one.
DetachedHandles detachFrom(BuildContext context) => (
  providers: ProviderScope.containerOf(context, listen: false),
  messenger: ScaffoldMessenger.of(context),
);
