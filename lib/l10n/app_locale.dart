import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale, basicLocaleListResolution;

import 'app_localizations.dart';

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
