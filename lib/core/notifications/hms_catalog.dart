import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;

import '../models/printer_status.dart';

/// HMS error descriptions bundled as assets (`assets/hms/`), loaded lazily and
/// cached per isolate.
///
/// Holds the faults bambuddy's own UI names and no others: the 32-bit
/// `print_error` channel keyed by its 8-hex code, plus the one 16-hex code
/// bambuddy adds by hand. See `tool/fetch_print_error_catalog.py`.
class HmsCatalog {
  HmsCatalog();

  /// Shared instance per isolate (UI or background).
  static final HmsCatalog instance = HmsCatalog();

  Map<String, String> _map = const {};
  String? _loadedLang;

  /// Loads the table for the locale (pl→pl, others→en). Idempotent.
  Future<void> load(Locale locale) async {
    final lang = locale.languageCode == 'pl' ? 'pl' : 'en';
    if (_loadedLang == lang) return;
    try {
      final raw = await rootBundle.loadString(
        'assets/hms/print_errors_$lang.json',
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _map = {for (final e in decoded.entries) e.key: e.value.toString()};
    } on Object {
      // Missing or corrupt asset → empty table (every code then reads as
      // unknown, which hides the panel rather than filling it with raw hex).
      _map = const {};
    }
    _loadedLang = lang;
  }

  /// The code's description, or null when nothing names it: the lossless full
  /// code, then the short form for a `print_error` fault from a server too old
  /// to send `full_code`, then the English sentence a 1.2.5.4+ server attaches —
  /// last because this table is the localized one.
  ///
  /// Never the short form of an `hms[]` code (`hms_errors.py::lookup_fault`):
  /// no real one has an error group at or above 0x4000, where every
  /// `print_error` key sits, so the collapse only ever found a neighbouring
  /// fault's sentence (#2728).
  String? describe(HmsError e) {
    final full = e.fullCode?.toUpperCase();
    if (full != null) {
      final hit = _map[full];
      if (hit != null) return hit;
    }
    final short = e.isHmsChannel ? null : e.shortCode;
    final local = short == null ? null : _map[short.replaceAll('_', '')];
    return local ?? e.description;
  }
}

/// Whether an HMS error should be shown at all: only one the client can name,
/// which is parity with bambuddy's `filterKnownHMSErrors`.
///
/// One deliberate departure — bambuddy keeps an uncataloged fault when the
/// firmware offers actions for it, so an unnamed error can still get buttons.
/// A card headed by a bare hex code asks the user to gamble.
///
/// **No "recognized severity" escape hatch, deliberately.** Before #2728
/// `severity` was not the HMS level: bambuddy derived it as `(attr >> 8) & 0xF`,
/// BambuStudio's `part_id`, while the level lives in `code >> 16`. Against the bundled
/// catalog the two agree on 39% of codes, and 835 arrive as level 1 ("Fatal")
/// while being nothing of the sort — which is where the invented
/// `severity · module` label came from ("Fatal · mainboard" on a healthy X2D).
bool hmsIsDisplayable(HmsError e, {String? description}) =>
    (e.message?.trim().isNotEmpty ?? false) ||
    (description?.trim().isNotEmpty ?? false);

/// The faults on [status] worth putting in front of a user, in the order the
/// server listed them.
///
/// **A disconnected printer has none**, whatever its `hms_errors` still say:
/// [PrinterStatus.mergedWith] carries the codes through an outage on purpose,
/// so that the notification path can pause its clear-grace clock on them, and
/// this is the one place that answers "last-known, not live".
///
/// [describe] is required rather than defaulted to [HmsCatalog.instance]: the
/// home-screen widget and the notification isolate hold their own catalogue or
/// none, and a hidden fallback would hand them the UI isolate's instead.
List<HmsError> displayableHmsErrors(
  PrinterStatus? status, {
  required String? Function(HmsError)? describe,
}) {
  if (status == null || status.connected == false) return const [];
  return [
    for (final e in status.hmsErrors ?? const <HmsError>[])
      if (hmsIsDisplayable(e, description: describe?.call(e))) e,
  ];
}

/// The first fault worth showing, or null. Separate from [displayableHmsErrors]
/// so the walk stops at the first hit: the dashboard filter asks this of every
/// printer on every rebuild, the home widget on every publish.
HmsError? firstDisplayableHmsError(
  PrinterStatus? status, {
  required String? Function(HmsError)? describe,
}) {
  if (status == null || status.connected == false) return null;
  for (final e in status.hmsErrors ?? const <HmsError>[]) {
    if (hmsIsDisplayable(e, description: describe?.call(e))) return e;
  }
  return null;
}

/// Whether an HMS error should fire a NOTIFICATION — [hmsIsDisplayable] plus
/// bambuddy's rule for which levels count (`main.py::_hms_fault_counts`). One
/// physical fault makes the firmware emit several codes at once, most of them
/// undocumented, and a described code the card lists can still be too quiet to
/// wake anybody for.
///
/// Read from [HmsError.level], never `severity`: before #2728 the server sent
/// the part byte there, and the `severity >= 2` floor this used to mirror
/// dropped exactly the faults that stop a print.
bool hmsIsNotifiable(HmsError e, {String? description}) {
  final level = e.level;
  // A numeric code with no level is Bambu's "invalid" 0. A fault without `attr`
  // (the legacy `{code, message}` shape) is left to the text checks below.
  if (level == null && e.ecode != null) return false;
  // An `hms[]` notification without actions ("top cover open", "chamber hot,
  // fan up") can stand through a whole print. A `print_error` prompt at the
  // same level still counts, as it does on the server.
  if (level == 3 && e.isHmsChannel && e.actions.isEmpty) return false;
  if (e.message?.trim().isNotEmpty ?? false) return true;
  return description?.trim().isNotEmpty ?? false;
}

/// Human-readable error label WITHOUT the code: server message → whatever
/// [HmsCatalog.describe] resolved → null, never anything composed out of
/// `severity`/`module`. The printer card shows the code separately.
String? hmsLabel(HmsError e, {String? description}) {
  final msg = e.message?.trim();
  if (msg != null && msg.isNotEmpty) return msg;
  final desc = description?.trim();
  return (desc != null && desc.isNotEmpty) ? desc : null;
}

/// Best human-readable text for an HMS error in ONE line (for notifications).
/// Falls back to the bare code, which only the callers that bypass
/// [hmsIsDisplayable] can reach.
String hmsHumanText(HmsError e, {String? description}) =>
    hmsLabel(e, description: description) ?? e.displayCode;

/// URL to the Bambu wiki page for the given code.
///
/// Per-code pages exist for the `hms[]` channel only — its 16-hex code maps to
/// `hmscode/0500_0500_0001_0007`. A `print_error` fault has no page of its own
/// (every URL shape 404s), and its 8-hex `full_code` cannot be padded into one:
/// [HmsError.ecode] would compose 16 hex out of a 32-bit value that means
/// something else, which is how a link lands on a wiki page about a different
/// fault. Those get bambuddy's own answer — the HMS index.
String? hmsWikiUrl(HmsError e) {
  final full = e.fullCode;
  if (full != null && full.length == 8) return _hmsWikiHome;
  final ec = e.ecode;
  if (ec == null || ec.length != 16) return _hmsWikiHome;
  final dashed =
      '${ec.substring(0, 4)}_${ec.substring(4, 8)}'
      '_${ec.substring(8, 12)}_${ec.substring(12, 16)}';
  return 'https://wiki.bambulab.com/en/x1/troubleshooting/hmscode/$dashed';
}

const String _hmsWikiHome = 'https://wiki.bambulab.com/en/hms/home';
