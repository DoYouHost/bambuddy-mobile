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
  const DateTimeFormats._(this._locale, this.use24Hour);

  /// `alwaysUse24HourFormatOf`, not `MediaQuery.of`, which would subscribe the
  /// caller to every metric and rebuild the dashboard card on each frame of a
  /// keyboard animation. The locale comes off the view so a test can override it.
  factory DateTimeFormats.of(BuildContext context) => DateTimeFormats._resolve(
        View.of(context).platformDispatcher.locale,
        Localizations.localeOf(context),
        MediaQuery.alwaysUse24HourFormatOf(context),
      );

  factory DateTimeFormats.system() {
    final dispatcher = PlatformDispatcher.instance;
    return DateTimeFormats._resolve(
      dispatcher.locale,
      dispatcher.locale,
      dispatcher.alwaysUse24HourFormat,
    );
  }

  /// The system locale wins so a region the app has no translation for still
  /// gets its own field order (`en_GB` → `22/08/2026`); an untranslated system
  /// *language* falls back, or German month names would land in an English UI.
  factory DateTimeFormats._resolve(
    Locale systemLocale,
    Locale appLocale,
    bool use24Hour,
  ) {
    _ensureLocaleData();
    final preferred = _translatedLanguages.contains(systemLocale.languageCode)
        ? systemLocale
        : appLocale;
    return DateTimeFormats._(_intlName(preferred), use24Hour);
  }

  /// Visible for tests, which cannot move the platform's switches.
  @visibleForTesting
  factory DateTimeFormats.forTest({
    required String locale,
    required bool use24Hour,
  }) {
    _ensureLocaleData();
    return DateTimeFormats._(locale, use24Hour);
  }

  final String _locale;

  /// False does not mean 12-hour — it hands the choice to the locale, and `pl`
  /// reads 24-hour either way.
  final bool use24Hour;

  // What each of these actually renders, per locale and clock setting, is
  // pinned in test/core/format/datetime_format_test.dart. The `named` variants
  // spell the month out, for places that read as prose rather than as a column
  // of stamps.

  String time(DateTime at) => _time.format(at);

  String date(DateTime at) => _cached('yMd', DateFormat.yMd).format(at);

  String dateTime(DateTime at) => '${date(at)} ${time(at)}';

  String dateNamedMonth(DateTime at) =>
      _cached('yMMMd', DateFormat.yMMMd).format(at);

  String dateNamedMonthTime(DateTime at) => '${dateNamedMonth(at)} ${time(at)}';

  String dayNamedMonth(DateTime at) =>
      _cached('MMMd', DateFormat.MMMd).format(at);

  String dayMonthNumeric(DateTime at) =>
      _cached('Md', DateFormat.Md).format(at);

  String monthAbbr(DateTime at) => _cached('MMM', DateFormat.MMM).format(at);

  /// Takes the hour rather than a [DateTime] because the caller is labelling a
  /// bucket, not an instant, and no particular day is meant.
  String hourOfDay(int hour) => use24Hour
      ? '${hour.toString().padLeft(2, '0')}:00'
      : _cached('j', DateFormat.j).format(DateTime(2000, 1, 1, hour));

  /// `dateSymbols` orders weekdays Sunday first, which no grid here draws.
  List<String> get shortWeekdaysMondayFirst {
    final sundayFirst =
        _cached('E', DateFormat.E).dateSymbols.STANDALONESHORTWEEKDAYS;
    return [...sundayFirst.skip(1), sundayFirst.first];
  }

  /// A finish time, dropping the date while it is still today. Crossing
  /// midnight is exactly when "21:20" alone becomes a lie.
  String clockOnDay(DateTime at, {required DateTime now}) {
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? time(at) : '${dayMonthNumeric(at)} ${time(at)}';
  }

  DateFormat get _time => use24Hour
      ? _cached('Hm', DateFormat.Hm)
      : _cached('jm', DateFormat.jm);

  /// A chart axis formats one label per tick on every paint, and building a
  /// [DateFormat] re-verifies the locale and re-parses the pattern each time.
  /// They hold no per-call state, so one per skeleton and locale is enough.
  static final Map<String, DateFormat> _formatCache = {};

  DateFormat _cached(String skeleton, DateFormat Function(String) build) =>
      _formatCache.putIfAbsent('$skeleton/$_locale', () => build(_locale));

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
