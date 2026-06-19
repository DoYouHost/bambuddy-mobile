import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;

import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';

/// Katalog opisów kodów HMS Bambu, zbundlowany jako asset (`assets/hms/`).
/// Mapa `ecode (16 hex) → opis`, scalona z oficjalnych zasobów BambuStudio
/// (PL + EN, wszystkie rodziny drukarek). Ładowana leniwie i cache'owana —
/// działa tak samo w isolacie UI jak w isolacie tła (każdy ma własną instancję).
class HmsCatalog {
  HmsCatalog();

  /// Współdzielona instancja na isolate (UI lub tło).
  static final HmsCatalog instance = HmsCatalog();

  Map<String, String> _map = const {};
  String? _loadedLang;

  /// Wczytuje tabelę dla języka locale (pl→pl, reszta→en). Idempotentne.
  Future<void> load(Locale locale) async {
    final lang = locale.languageCode == 'pl' ? 'pl' : 'en';
    if (_loadedLang == lang) return;
    try {
      final raw = await rootBundle.loadString('assets/hms/hms_$lang.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _map = {for (final e in decoded.entries) e.key: e.value.toString()};
    } on Object {
      // Brak/uszkodzony asset → pusty katalog (fallback do formatu kodu).
      _map = const {};
    }
    _loadedLang = lang;
  }

  /// Opis kodu z tabeli lub null, gdy nieznany / katalog niezaładowany.
  String? describe(HmsError e) {
    final ec = e.ecode;
    if (ec == null) return null;
    return _map[ec];
  }
}

/// Czy błąd HMS jest wart pokazania użytkownikowi (parytet z bambuddy, które
/// NIE wyświetla wpisów wewnętrznych). Pokazujemy, gdy:
///  • serwer dał wiadomość, albo
///  • kod rozwiązuje się w katalogu (znany błąd), albo
///  • severity jest rozpoznanym poziomem Bambu (1 fatal…4 info).
/// Obserwacja z żywego serwera: nieprzetłumaczalne/wewnętrzne wpisy przychodzą
/// z nietypowym `severity` (np. 6) i bez wiadomości — te chowamy.
bool hmsIsDisplayable(HmsError e, {String? description}) {
  if ((e.message?.trim().isNotEmpty ?? false)) return true;
  if ((description?.trim().isNotEmpty ?? false)) return true;
  final s = e.severity;
  return s != null && s >= 1 && s <= 4;
}

/// Czytelna etykieta błędu BEZ kodu: wiadomość z serwera → opis z katalogu →
/// „poziom · moduł". null, gdy nic z tego nie jest znane (zostaje sam kod).
/// Używane przez kartę, gdzie kod pokazujemy osobno (z linkiem do wiki).
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

/// Najlepszy czytelny tekst dla błędu HMS w JEDNEJ linii (powiadomienie):
/// [hmsLabel] + kod w nawiasie, lub sam kod. Nigdy surowy hex bez kontekstu.
String hmsHumanText(
  HmsError e, {
  String? description,
  required AppLocalizations l10n,
}) {
  final label = hmsLabel(e, description: description, l10n: l10n);
  if (label == null) return e.displayCode;
  // Wiadomość/opis bywa pełnym zdaniem — nie doklejamy do niego kodu.
  final hasText = (e.message?.trim().isNotEmpty ?? false) ||
      (description?.trim().isNotEmpty ?? false);
  return hasText ? label : '$label (${e.displayCode})';
}

/// Etykieta poziomu ważności HMS (Bambu: 1 fatal, 2 serious, 3 common, 4 info).
/// null dla nieznanej wartości — wtedy pomijamy w tekście.
String? hmsSeverityLabel(int? severity, AppLocalizations l10n) => switch (severity) {
      1 => l10n.hmsSeverityFatal,
      2 => l10n.hmsSeveritySerious,
      3 => l10n.hmsSeverityCommon,
      4 => l10n.hmsSeverityInfo,
      _ => null,
    };

/// Etykieta modułu/podsystemu HMS. null dla nieznanego.
String? hmsModuleLabel(int? module, AppLocalizations l10n) => switch (module) {
      0x03 => l10n.hmsModuleMc,
      0x05 => l10n.hmsModuleMainboard,
      0x07 => l10n.hmsModuleAms,
      0x08 => l10n.hmsModuleToolhead,
      0x0C => l10n.hmsModuleXcam,
      _ => null,
    };

/// Link do strony wiki Bambu dla danego kodu (format z podkreśleniami).
/// null, gdy nie da się złożyć pełnego 16-hex kodu.
String? hmsWikiUrl(HmsError e) {
  final ec = e.ecode;
  if (ec == null || ec.length != 16) return null;
  final dashed = '${ec.substring(0, 4)}_${ec.substring(4, 8)}'
      '_${ec.substring(8, 12)}_${ec.substring(12, 16)}';
  return 'https://wiki.bambulab.com/en/x1/troubleshooting/hmscode/$dashed';
}
