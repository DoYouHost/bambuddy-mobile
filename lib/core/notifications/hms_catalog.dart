import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;

import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';

/// Catalog of HMS error code descriptions bundled as assets (`assets/hms/`).
/// Maps `ecode (16 hex) → description`, merged from official BambuStudio resources
/// (PL + EN, all printer families). Loaded lazily and cached — works the same
/// in the UI isolate and background isolate (each has its own instance).
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
      final raw = await rootBundle.loadString('assets/hms/hms_$lang.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _map = {for (final e in decoded.entries) e.key: e.value.toString()};
    } on Object {
      // Missing or corrupt asset → empty catalog (fallback to code format).
      _map = const {};
    }
    _loadedLang = lang;
  }

  /// Returns the code description from the table, or null if unknown/not loaded.
  String? describe(HmsError e) {
    final ec = e.ecode;
    if (ec == null) return null;
    return _map[ec];
  }
}

/// Whether an HMS error should be shown to the user (matches bambuddy's behavior:
/// does NOT display internal errors). Show if:
///  • server provided a message, OR
///  • code resolves in the catalog (known error), OR
///  • severity is a recognized Bambu level (1 fatal…4 info).
/// Live observation: untranslatable/internal entries come with unusual severity
/// (e.g., 6) and no message — we hide these.
bool hmsIsDisplayable(HmsError e, {String? description}) {
  if ((e.message?.trim().isNotEmpty ?? false)) return true;
  if ((description?.trim().isNotEmpty ?? false)) return true;
  final s = e.severity;
  return s != null && s >= 1 && s <= 4;
}

/// Whether an HMS error should fire a NOTIFICATION — stricter than
/// [hmsIsDisplayable]. Parity with bambuddy's notification path, which pushes an
/// error ONLY when it resolves to a known description ("Only notify for errors
/// with known descriptions — printers send many undocumented/phantom codes that
/// aren't real errors"). One physical fault (filament runout, open door) makes
/// the firmware emit several codes at once, most of them undocumented; gating on
/// a real description collapses that to the one meaningful alert. The card stays
/// on the looser [hmsIsDisplayable] so it can still list raw codes with a wiki
/// link.
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

/// Human-readable error label WITHOUT the code: server message → catalog description →
/// "severity · module". null if nothing is known (only code remains).
/// Used by the printer card, which shows the code separately (with wiki link).
String? hmsLabel(
  HmsError e, {
  String? description,
  required AppLocalizations l10n,
}) {
  final msg = e.message?.trim();
  if (msg != null && msg.isNotEmpty) return msg;
  if (description != null && description.trim().isNotEmpty) {
    return description.trim();
  }
  final parts = <String>[];
  final sev = hmsSeverityLabel(e.severity, l10n);
  final mod = hmsModuleLabel(e.module, l10n);
  if (sev != null) parts.add(sev);
  if (mod != null) parts.add(mod);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Best human-readable text for an HMS error in ONE line (for notifications):
/// [hmsLabel] + code in parentheses, or code alone. Never bare hex without context.
String hmsHumanText(
  HmsError e, {
  String? description,
  required AppLocalizations l10n,
}) {
  final label = hmsLabel(e, description: description, l10n: l10n);
  if (label == null) return e.displayCode;
  // When message/description is a full sentence, don't append the code.
  final hasText = (e.message?.trim().isNotEmpty ?? false) ||
      (description?.trim().isNotEmpty ?? false);
  return hasText ? label : '$label (${e.displayCode})';
}

/// Label for HMS severity level (Bambu: 1 fatal, 2 serious, 3 common, 4 info).
/// null for unknown values — omitted from text in those cases.
String? hmsSeverityLabel(int? severity, AppLocalizations l10n) => switch (severity) {
      1 => l10n.hmsSeverityFatal,
      2 => l10n.hmsSeveritySerious,
      3 => l10n.hmsSeverityCommon,
      4 => l10n.hmsSeverityInfo,
      _ => null,
    };

/// Label for HMS module/subsystem. null for unknown.
String? hmsModuleLabel(int? module, AppLocalizations l10n) => switch (module) {
      0x03 => l10n.hmsModuleMc,
      0x05 => l10n.hmsModuleMainboard,
      0x07 => l10n.hmsModuleAms,
      0x08 => l10n.hmsModuleToolhead,
      0x0C => l10n.hmsModuleXcam,
      _ => null,
    };

/// URL to the Bambu wiki page for the given code (underscore-separated format).
/// null if unable to construct the full 16-hex code.
String? hmsWikiUrl(HmsError e) {
  final ec = e.ecode;
  if (ec == null || ec.length != 16) return null;
  final dashed = '${ec.substring(0, 4)}_${ec.substring(4, 8)}'
      '_${ec.substring(8, 12)}_${ec.substring(12, 16)}';
  return 'https://wiki.bambulab.com/en/x1/troubleshooting/hmscode/$dashed';
}
