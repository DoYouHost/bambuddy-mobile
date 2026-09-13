import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale, basicLocaleListResolution;

import 'app_localizations.dart';

/// The app's language for code outside the widget tree — notifications, the
/// foreground service isolate, HMS catalog loading — where there is no
/// `BuildContext` for `AppLocalizations.of`.
Locale systemLocale() => resolveAppLocale(PlatformDispatcher.instance.locales);

/// `lookupAppLocalizations` throws on an unsupported language, so it is only
/// ever handed a resolved locale.
AppLocalizations systemAppLocalizations() =>
    lookupAppLocalizations(systemLocale());

/// The same resolution `MaterialApp` applies to `supportedLocales`, so text
/// built outside the tree speaks the language of the screen it opens —
/// including the second preferred system language and the `en` fallback.
Locale resolveAppLocale(List<Locale> preferred) =>
    basicLocaleListResolution(preferred, AppLocalizations.supportedLocales);
