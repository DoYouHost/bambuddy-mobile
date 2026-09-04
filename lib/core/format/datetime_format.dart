import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

/// Derived rather than listed, so adding a translation does not leave this
/// behind — a language missing here silently loses its region formatting.
final Set<String> _translatedLanguages = {
  for (final l in AppLocalizations.supportedLocales) l.languageCode,
};

/// Every user-visible date and time in the app is spelled by one of these, from
/// the system locale and the system 24-hour switch rather than a hardcoded
/// pattern. Use [DateTimeFormats.of] in the widget tree, [DateTimeFormats.system]
/// outside it (background isolate, home widget publisher).
@immutable
class DateTimeFormats {
  const DateTimeFormats._(this._locale, this._wordLocale, this._use24Hour);

  /// `alwaysUse24HourFormatOf`, not `MediaQuery.of`, which would subscribe the
  /// caller to every metric and rebuild the dashboard card on each frame of a
  /// keyboard animation. The locale comes off the view so a test can override it.
  ///
  /// Reading the platform locale registers no dependency, and `Localizations`
  /// notifies only when the *resolved* locale changes — so a region-only switch
  /// (`en_US` → `en_GB`, both resolving to `en`) reaches the screen on its next
  /// rebuild rather than at once. Everything here is rebuilt by ordinary
  /// navigation, so no observer earns its keep.
  factory DateTimeFormats.of(BuildContext context) => DateTimeFormats._resolve(
        View.of(context).platformDispatcher.locale,
        Localizations.localeOf(context),
        MediaQuery.alwaysUse24HourFormatOf(context),
      );

  /// No app locale is knowable outside the tree, so an untranslated system
  /// language falls back to `en` — the same fallback `lib/app.dart` declares.
  ///
  /// The clock cannot come off the dispatcher here. Only an engine that hosts a
  /// view is ever sent the user settings, and the foreground service runs a bare
  /// `FlutterEngine`: `alwaysUse24HourFormat` keeps its Dart-side default of
  /// false there, which is how every notification ETA came out as `8:29 PM` on a
  /// phone set to 24 hours. So the value is published from the widget tree
  /// ([rememberSystemClock], via `SystemClockSync`) and read back from
  /// preferences by the service. A `true` from the dispatcher is still worth
  /// taking — nothing but the real setting produces one — and with neither,
  /// [use24Hour] asks the locale.
  factory DateTimeFormats.system() {
    final dispatcher = PlatformDispatcher.instance;
    return DateTimeFormats._resolve(
      dispatcher.locale,
      const Locale('en'),
      isolateClock(
        remembered: _rememberedClock,
        dispatcherSays: dispatcher.alwaysUse24HourFormat,
      ),
    );
  }

  /// Which clock an isolate outside the widget tree can be *sure* of, or null
  /// when it cannot be sure of one and [use24Hour] has to ask the locale.
  ///
  /// A rule of its own because it cannot be reached through [system]: that reads
  /// `PlatformDispatcher.instance`, which is the process-wide singleton and
  /// ignores the test values a widget test sets on its own dispatcher — so the
  /// only way to pin this is to call it directly.
  ///
  /// [remembered] is what the tree published ([rememberSystemClock]) or what the
  /// service read back out of preferences, and it wins outright: it is the only
  /// source out here that has actually seen the user's setting.
  /// [dispatcherSays] is the engine's own flag, which reads `false` both for a
  /// phone on a 12-hour clock and for an engine nobody ever told — the bare
  /// `FlutterEngine` the foreground service runs. Only a `true` can have come
  /// from the real setting, so a `true` is taken and a `false` is discarded as
  /// the non-answer it usually is.
  @visibleForTesting
  static bool? isolateClock({
    required bool? remembered,
    required bool dispatcherSays,
  }) =>
      remembered ?? (dispatcherSays ? true : null);

  /// What the platform's 12/24-hour switch says, for the isolates that cannot
  /// ask it themselves. Null means nobody has said — [use24Hour] then falls back
  /// to the locale rather than to a silent "12-hour".
  static bool? _rememberedClock;

  static void rememberSystemClock(bool? use24Hour) =>
      _rememberedClock = use24Hour;

  /// Digits and words resolve differently. Field order is the device's business
  /// whatever language it is set to, so numbers keep the system locale — a
  /// `de_DE` phone gets `8.5.2026`, not the US `5/8/2026` it would read as a
  /// different day. Month and weekday names have to come from a language we
  /// translate, or German words would land in an English UI.
  factory DateTimeFormats._resolve(
    Locale systemLocale,
    Locale appLocale,
    bool? use24Hour,
  ) {
    _ensureLocaleData();
    final translated = _translatedLanguages.contains(systemLocale.languageCode);
    return DateTimeFormats._(
      _intlName(systemLocale),
      _intlName(translated ? systemLocale : appLocale),
      use24Hour,
    );
  }

  /// Visible for tests, which cannot move the platform's switches.
  @visibleForTesting
  factory DateTimeFormats.forTest({
    required String locale,
    bool? use24Hour,
    String? wordLocale,
  }) {
    _ensureLocaleData();
    return DateTimeFormats._(locale, wordLocale ?? locale, use24Hour);
  }

  /// Numeric field order — the system locale, translated or not.
  final String _locale;

  /// Where a month name, weekday name or am/pm marker comes from.
  final String _wordLocale;

  /// Android hands us the *resolved* setting, not the raw switch: with nothing
  /// chosen it already answers the locale's own convention. So false is a real
  /// "12-hour" and is forced as one — deferring to the locale (which is what
  /// `TimeOfDay.format` does) would ignore a `pl` user who went and picked
  /// 12-hour by hand. Null is the other thing entirely: not a setting, but an
  /// isolate that has no way to read one.
  final bool? _use24Hour;

  /// The switch where it could be read, the locale's own convention where it
  /// could not — never a hardcoded 12-hour clock, which is what a `pl` phone was
  /// getting in its notifications.
  bool get use24Hour => _use24Hour ?? _localeUses24Hour(_locale);

  // What each of these actually renders, per locale and clock setting, is
  // pinned in test/core/format/datetime_format_test.dart. The `named` variants
  // spell the month out, for places that read as prose rather than as a column
  // of stamps.

  String time(DateTime at) => _time.format(at);

  String date(DateTime at) => _cached('yMd', DateFormat.yMd).format(at);

  String dateTime(DateTime at) => '${date(at)} ${time(at)}';

  String dateNamedMonth(DateTime at) =>
      _cachedWords('yMMMd', DateFormat.yMMMd).format(at);

  String dateNamedMonthTime(DateTime at) => '${dateNamedMonth(at)} ${time(at)}';

  String dayNamedMonth(DateTime at) =>
      _cachedWords('MMMd', DateFormat.MMMd).format(at);

  String dayMonthNumeric(DateTime at) =>
      _cached('Md', DateFormat.Md).format(at);

  String monthAbbr(DateTime at) =>
      _cachedWords('MMM', DateFormat.MMM).format(at);

  /// Takes the hour rather than a [DateTime] because the caller is labelling a
  /// bucket, not an instant, and no particular day is meant. Goes through the
  /// same format as [time] instead of an hour-only one: `DateFormat.j` drops the
  /// minutes, and a bare `06` on an axis reads as a day number.
  String hourOfDay(int hour) => time(DateTime(2000, 1, 1, hour));

  /// `dateSymbols` orders weekdays Sunday first, which no grid here draws.
  List<String> get shortWeekdaysMondayFirst {
    final sundayFirst =
        _cachedWords('E', DateFormat.E).dateSymbols.STANDALONESHORTWEEKDAYS;
    return [...sundayFirst.skip(1), sundayFirst.first];
  }

  /// A finish time, dropping the date while it is still today. Crossing
  /// midnight is exactly when "21:20" alone becomes a lie.
  String clockOnDay(DateTime at, {required DateTime now}) {
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? time(at) : '${dayMonthNumeric(at)} ${time(at)}';
  }

  /// The 12-hour branch spells the pattern out rather than using the `jm`
  /// skeleton, which would hand the hour cycle back to the locale — the one
  /// thing [use24Hour] has already settled. `en_GB` has perfectly good `am`/`pm`
  /// markers but a 24-hour `jm`, so the skeleton cannot be asked.
  DateFormat get _time {
    if (use24Hour) return _cached('Hm', DateFormat.Hm);
    final locale = _clockLocale(_wordLocale);
    return _formatCache.putIfAbsent(
        'h:mm a/$locale', () => DateFormat('h:mm a', locale));
  }

  static final Map<String, bool> _localeClockCache = {};

  /// The locale's own hour cycle, read off its `jm` pattern: `H` (0-23) and `k`
  /// (1-24) are the 24-hour hour fields, `h` and `K` the 12-hour ones. Quoted
  /// runs are dropped first — a letter inside one is literal text, not a field.
  static bool _localeUses24Hour(String locale) =>
      _localeClockCache.putIfAbsent(locale, () {
        final pattern = (DateFormat.jm(locale).pattern ?? '')
            .replaceAll(RegExp(r"'[^']*'"), '');
        return pattern.contains('H') || pattern.contains('k');
      });

  static final Map<String, String> _clockLocaleCache = {};

  /// intl ships some locales' am/pm markers as single letters (`pl` → `a`/`p`),
  /// which reads as a typo next to a time. Android shows `AM`/`PM` there — its
  /// ICU data carries the abbreviated form intl lacks — so borrow English
  /// markers whenever the locale's own are that thin.
  static String _clockLocale(String wordLocale) =>
      _clockLocaleCache.putIfAbsent(wordLocale, () {
        final markers = DateFormat.jm(wordLocale).dateSymbols.AMPMS;
        final thin = markers.any((m) => m.trim().length < 2);
        return thin ? 'en' : wordLocale;
      });

  /// A chart axis formats one label per tick on every paint, and building a
  /// [DateFormat] re-verifies the locale and re-parses the pattern each time.
  /// They hold no per-call state, so one per skeleton and locale is enough.
  static final Map<String, DateFormat> _formatCache = {};

  DateFormat _cached(String skeleton, DateFormat Function(String) build) =>
      _formatCache.putIfAbsent('$skeleton/$_locale', () => build(_locale));

  DateFormat _cachedWords(String skeleton, DateFormat Function(String) build) =>
      _formatCache.putIfAbsent(
          '$skeleton/$_wordLocale', () => build(_wordLocale));

  /// `Locale.toString` already joins with `_`, but a script subtag would make a
  /// name `intl` has no data for, and the language alone always resolves.
  static String _intlName(Locale locale) {
    final country = locale.countryCode;
    if (country == null || country.isEmpty) return locale.languageCode;
    return '${locale.languageCode}_$country';
  }

  static bool _localeDataReady = false;

  /// `flutter_localizations` loads `intl`'s locale data, but only once a
  /// `Localizations` widget has resolved — the background isolate and the home
  /// widget publisher never get that far and would format everything as en_US.
  static void _ensureLocaleData() {
    if (_localeDataReady) return;
    initializeDateFormatting();
    _localeDataReady = true;
  }
}
