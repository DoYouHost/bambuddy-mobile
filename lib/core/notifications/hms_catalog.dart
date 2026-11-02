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

  /// The code's description, or null when nothing names it: the lossless full code,
  /// then the short form (a `print_error` fault only, never an `hms[]` code, #2728),
  /// then the server's English sentence, last because this table is the localized one
  /// (docs/notification-delivery.md, "Which HMS faults count").
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

/// Whether an HMS error should be shown at all: only one the client can name, as
/// bambuddy's `filterKnownHMSErrors`, except that an uncataloged fault with actions
/// is dropped too. No "recognized severity" escape hatch: `severity` was not the HMS
/// level before #2728 (docs/notification-delivery.md, "Which HMS faults count").
bool hmsIsDisplayable(HmsError e, {String? description}) =>
    (e.message?.trim().isNotEmpty ?? false) ||
    (description?.trim().isNotEmpty ?? false);

/// The faults on [status] worth putting in front of a user, in the order the server
/// listed them. **A disconnected printer has none**: its codes are last-known, not
/// live. [describe] is required, not defaulted to [HmsCatalog.instance], so no isolate
/// is handed another's catalogue (docs/notification-delivery.md, "Which HMS faults count").
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
/// bambuddy's level rule (`main.py::_hms_fault_counts`). Read from [HmsError.level],
/// never `severity` (docs/notification-delivery.md, "Which HMS faults count").
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

/// URL to the Bambu wiki page for the given code. Per-code pages exist for the
/// `hms[]` channel only; a `print_error` fault gets bambuddy's own answer, the HMS
/// index (docs/notification-delivery.md, "Which HMS faults count").
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
