import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;

import '../models/printer_status.dart';

/// Catalog of HMS error code descriptions bundled as assets (`assets/hms/`).
/// Loaded lazily and cached — works the same in the UI isolate and background
/// isolate (each has its own instance).
///
/// Holds the same set of faults bambuddy's own UI names and no others: the
/// 32-bit `print_error` channel, keyed by its 8-hex code, plus the single
/// 16-hex code bambuddy adds by hand. Bambu's texts, in PL and EN — see
/// `tool/fetch_print_error_catalog.py` for where each half comes from.
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
      final raw =
          await rootBundle.loadString('assets/hms/print_errors_$lang.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _map = {for (final e in decoded.entries) e.key: e.value.toString()};
    } on Object {
      // Missing or corrupt asset → empty table (every code then reads as
      // unknown, which hides the panel rather than filling it with raw hex).
      _map = const {};
    }
    _loadedLang = lang;
  }

  /// Returns the code description, or null if unknown/not loaded. Lookup order
  /// is the server's own (`HMSErrorModal.tsx::lookupDescription`): the lossless
  /// full code first, the lossy short form as the fallback that carries the
  /// bulk of the table.
  ///
  /// A code this table does not name falls back to [HmsError.description], the
  /// sentence a 1.2.5.4+ server attaches to the fault itself. The bundled table
  /// stays first because it is localized and the server's is English only, so
  /// the fallback only ever replaces *no text at all* — which, through
  /// [hmsIsDisplayable], is the difference between a named fault and a card the
  /// app refuses to show.
  String? describe(HmsError e) {
    final full = e.fullCode?.toUpperCase();
    if (full != null) {
      final hit = _map[full];
      if (hit != null) return hit;
    }
    final short = e.shortCode;
    final local = short == null ? null : _map[short.replaceAll('_', '')];
    return local ?? e.description;
  }
}

/// Whether an HMS error should be shown to the user. An error the client cannot
/// name is not shown at all — parity with bambuddy's `filterKnownHMSErrors`,
/// which drops every code missing from its description table so it never turns
/// an unrecognized code into a red card. Show if:
///  • server provided a message, OR
///  • the code resolves through [HmsCatalog.describe] — our table or, failing
///    that, the sentence the server itself attached to the fault.
///
/// One deliberate departure from bambuddy: it keeps an uncataloged fault when
/// the firmware offers actions for it, so an unnamed error can still get
/// buttons. The app does not — a card headed by a bare hex code, no matter what
/// it offers to do about it, asks the user to gamble.
///
/// There is deliberately no "recognized severity" escape hatch. `severity` is
/// not the HMS level: bambuddy derives it as `(attr >> 8) & 0xF`, which is
/// BambuStudio's `part_id`, while the real level lives in `code >> 16`. Scored
/// against the bundled catalog the two agree on 39% of codes, and 835 of them
/// come through as level 1 ("Fatal") while being nothing of the sort. So the
/// field says nothing about whether a code is a real fault, and the
/// `severity · module` label it used to feed ("Fatal · mainboard" for an X2D
/// status message) was invented text on top of an invented number.
bool hmsIsDisplayable(HmsError e, {String? description}) =>
    (e.message?.trim().isNotEmpty ?? false) ||
    (description?.trim().isNotEmpty ?? false);

/// The faults on [status] worth putting in front of a user, in the order the
/// server listed them.
///
/// **A disconnected printer has none**, whatever its `hms_errors` still say.
/// [PrinterStatus.mergedWith] carries the codes through an outage on purpose —
/// the notification path pauses its clear-grace clock on them, so a fault known
/// before the outage does not re-alert on reconnect — which leaves every surface
/// on the hook for answering "these are last-known values, not live faults".
/// Four of them were answering it in four different wordings; this is the one
/// place that answers it now.
///
/// [describe] is required rather than defaulted to [HmsCatalog.instance]: the
/// home-screen widget and the notification isolate hold their own catalogue, or
/// none at all — `null` is then the honest answer — and a hidden fallback would
/// quietly hand them the UI isolate's instead.
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

/// The first fault worth showing, or null — [displayableHmsErrors] for a caller
/// that only needs to know *whether* there is one, or which one is on top.
///
/// Separate function rather than `displayableHmsErrors(...).firstOrNull` so the
/// walk stops at the first hit: the dashboard filter asks this of every printer
/// on every rebuild, and the home widget asks it on every publish, including
/// from the notification isolate.
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

/// Whether an HMS error should fire a NOTIFICATION — stricter than
/// [hmsIsDisplayable]. Parity with bambuddy's notification path, which pushes an
/// error ONLY when it resolves to a known description ("Only notify for errors
/// with known descriptions — printers send many undocumented/phantom codes that
/// aren't real errors"). One physical fault (filament runout, open door) makes
/// the firmware emit several codes at once, most of them undocumented; gating on
/// a real description collapses that to the one meaningful alert. Stricter than
/// the card only in the severity floor below — a described code the card lists
/// can still be too quiet to be worth waking anybody for.
bool hmsIsNotifiable(HmsError e, {String? description}) {
  // Severity floor — parity with bambuddy's notification path, which alerts only
  // for `severity >= 2` and drops severity-1 codes as "informational/status
  // messages" (backend derives severity from `(attr >> 8) & 0xF`). Live WS frames
  // always carry a severity, so this floor applies. A null severity only occurs on
  // the legacy `{code, message}` shape — leave that to the message check below.
  final sev = e.severity;
  if (sev != null && sev < 2) return false;
  if (e.message?.trim().isNotEmpty ?? false) return true;
  return description?.trim().isNotEmpty ?? false;
}

/// Human-readable error label WITHOUT the code: server message → whatever
/// [HmsCatalog.describe] resolved. null when neither is known — and such an
/// error is not shown at all ([hmsIsDisplayable]), so nothing is composed out of
/// `severity`/`module` to stand in for it.
/// Used by the printer card, which shows the code separately (with wiki link).
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
  final dashed = '${ec.substring(0, 4)}_${ec.substring(4, 8)}'
      '_${ec.substring(8, 12)}_${ec.substring(12, 16)}';
  return 'https://wiki.bambulab.com/en/x1/troubleshooting/hmscode/$dashed';
}

const String _hmsWikiHome = 'https://wiki.bambulab.com/en/hms/home';
