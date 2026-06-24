import 'package:home_widget/home_widget.dart';

import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';
import '../notifications/hms_catalog.dart';

/// Publikuje stan jednej (wybranej) drukarki do natywnego widgetu ekranu
/// głównego (`BambuddyWidgetProvider`). Zasilany z DWÓCH torów: providera UI na
/// pierwszym planie ([printerStatusesProvider]) oraz isolate'u tła (foreground
/// service). Oba wołają [publish] przy każdej świeżej ramce — `home_widget`
/// zapisuje dane do współdzielonych SharedPreferences i odświeża widget.
///
/// Świadomie prosty: widget pokazuje JEDNĄ drukarkę (preferuje aktywnie
/// drukującą, w przeciwnym razie pierwszą po `id`). Dane dynamiczne (nazwy,
/// etykieta statusu) lecą już zlokalizowane z Darta — natywna strona ich nie
/// tłumaczy, dba tylko o układ i kolor kropki statusu (po `status_key`).
class HomeWidgetPublisher {
  /// Nazwa klasy [AppWidgetProvider] po stronie Androida (pakiet wnioskowany
  /// z applicationId). `home_widget` używa jej do `updateWidget`.
  static const String _androidProvider = 'BambuddyWidgetProvider';

  /// Klucze statusu — muszą się zgadzać z mapą kolorów w Kotlinie.
  static const String _kPrinting = 'printing';
  static const String _kPaused = 'paused';
  static const String _kFinished = 'finished';
  static const String _kFailed = 'failed';
  static const String _kIdle = 'idle';
  static const String _kOffline = 'offline';
  static const String _kError = 'error';

  /// Zapisuje stan wybranej drukarki i odświeża widget. Bezpieczne do wołania
  /// często — sam plugin debouncuje zapis, a `updateWidget` jest tani.
  ///
  /// [describeHms] — opis błędu HMS z katalogu (foreground: `HmsCatalog.instance`,
  /// tło: lokalny katalog isolate'u). [fetchCover] — pobranie okładki wydruku do
  /// pliku (auth tokenem kamery); różne per isolate, więc wstrzykiwane. Oba
  /// opcjonalne — bez nich widget po prostu pomija błąd HMS / miniaturę.
  static Future<void> publish(
    Map<int, PrinterStatus> statuses,
    AppLocalizations l10n, {
    String? Function(HmsError)? describeHms,
    Future<String?> Function(PrinterStatus picked)? fetchCover,
  }) async {
    final picked = _select(statuses);

    if (picked == null) {
      await HomeWidget.saveWidgetData<String>('status_key', _kOffline);
      await HomeWidget.saveWidgetData<String>(
          'printer_name', l10n.widgetNoPrinter);
      await HomeWidget.saveWidgetData<String>('print_name', '');
      await HomeWidget.saveWidgetData<String>(
          'status_label', l10n.statusUnavailable);
      await HomeWidget.saveWidgetData<String>('eta', '');
      await HomeWidget.saveWidgetData<String>('layers', '');
      await HomeWidget.saveWidgetData<String>('cover_path', '');
      await HomeWidget.saveWidgetData<int>('progress', 0);
      await HomeWidget.saveWidgetData<bool>('printing', false);
    } else {
      final baseKey = _statusKey(picked);
      final printing = baseKey == _kPrinting || baseKey == _kPaused;

      // Aktywny błąd HMS nadpisuje status (czerwona kropka + treść błędu),
      // ale postęp/ETA dalej pokazujemy, jeśli drukarka mimo to drukuje.
      final hms = _topHmsError(picked, describeHms);
      final key = hms != null ? _kError : baseKey;
      final statusLabel = hms != null
          ? hmsHumanText(hms, description: describeHms?.call(hms), l10n: l10n)
          : _statusLabel(l10n, key);

      await HomeWidget.saveWidgetData<String>('status_key', key);
      await HomeWidget.saveWidgetData<String>(
          'printer_name', picked.name ?? l10n.widgetNoPrinter);
      await HomeWidget.saveWidgetData<String>(
          'print_name', _printName(picked, l10n, baseKey));
      await HomeWidget.saveWidgetData<String>('status_label', statusLabel);
      await HomeWidget.saveWidgetData<String>(
          'eta', _eta(picked, l10n, baseKey));
      await HomeWidget.saveWidgetData<String>('layers', _layers(picked, baseKey));
      await HomeWidget.saveWidgetData<int>('progress', _progressPct(picked));
      await HomeWidget.saveWidgetData<bool>('printing', printing);

      // Okładkę ściągamy tylko podczas druku i tylko gdy serwer poda `cover_url`.
      // Pomijamy ją w fazie kalibracji (`auto_cali_*`) — taki przebieg nie ma
      // własnej okładki, więc inaczej widget pokazałby podgląd poprzedniego druku.
      var coverPath = '';
      if (printing &&
          picked.coverUrl != null &&
          !picked.isCalibration &&
          fetchCover != null) {
        coverPath = await fetchCover(picked) ?? '';
      }
      await HomeWidget.saveWidgetData<String>('cover_path', coverPath);
    }

    await HomeWidget.updateWidget(
      androidName: _androidProvider,
      qualifiedAndroidName:
          'page.codeberg.morganmlgman.bambuddy_mobile.$_androidProvider',
    );
  }

  /// Pierwszy „pokazywalny" błąd HMS (filtr severity 1..4 / z treścią — patrz
  /// [hmsIsDisplayable]), albo `null`. To samo kryterium co karta drukarki.
  static HmsError? _topHmsError(
    PrinterStatus s,
    String? Function(HmsError)? describeHms,
  ) {
    for (final e in s.hmsErrors ?? const <HmsError>[]) {
      if (hmsIsDisplayable(e, description: describeHms?.call(e))) return e;
    }
    return null;
  }

  /// Warstwy „X/Y" podczas druku, jeśli serwer poda oba pola. Inaczej pusto.
  static String _layers(PrinterStatus s, String key) {
    if (key != _kPrinting && key != _kPaused) return '';
    final cur = s.layerNum;
    final total = s.totalLayers;
    if (cur == null || total == null || total <= 0) return '';
    return '$cur/$total';
  }

  /// Wybiera drukarkę do pokazania: najpierw aktywnie drukującą (połączoną),
  /// w przeciwnym razie pierwszą po rosnącym `id`. `null`, gdy brak drukarek.
  static PrinterStatus? _select(Map<int, PrinterStatus> statuses) {
    if (statuses.isEmpty) return null;
    final sorted = statuses.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final s in sorted) {
      if ((s.connected ?? false) && s.isPrinting) return s;
    }
    return sorted.first;
  }

  static String _statusKey(PrinterStatus s) {
    if (!(s.connected ?? false)) return _kOffline;
    if (s.isPaused) return _kPaused;
    if (s.isPrinting) return _kPrinting;
    switch (s.state?.toUpperCase()) {
      case 'FINISH':
      case 'FINISHED':
        return _kFinished;
      case 'FAILED':
        return _kFailed;
    }
    return _kIdle;
  }

  static String _statusLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case _kPrinting:
        return l10n.widgetStatusPrinting;
      case _kPaused:
        return l10n.widgetStatusPaused;
      case _kFinished:
        return l10n.widgetStatusFinished;
      case _kFailed:
        return l10n.widgetStatusFailed;
      case _kOffline:
        return l10n.widgetStatusOffline;
      default:
        return l10n.widgetStatusIdle;
    }
  }

  /// Nazwa wydruku do pokazania: gdy drukuje — bieżący plik (lub etap, gdy
  /// jeszcze brak postępu); poza drukiem — pusto (UI ukrywa wiersz).
  static String _printName(
    PrinterStatus s,
    AppLocalizations l10n,
    String key,
  ) {
    if (key != _kPrinting && key != _kPaused) return '';
    final name = s.currentPrint ?? s.gcodeFile;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    // Faza przygotowania bez nazwy pliku — pokaż etap, jeśli serwer go poda.
    return s.stgCurName?.trim() ?? '';
  }

  /// Wiersz ETA: pozostały czas + godzina zakończenia (HH:mm). Pusty poza
  /// drukiem lub gdy serwer nie poda pozostałego czasu. Format jak na karcie
  /// drukarki (`durationMinutes`/`durationHoursMinutes`).
  static String _eta(PrinterStatus s, AppLocalizations l10n, String key) {
    if (key != _kPrinting && key != _kPaused) return '';
    final mins = s.remainingTime ?? 0;
    if (mins <= 0) return '';
    final dur = mins < 60
        ? l10n.durationMinutes(mins)
        : l10n.durationHoursMinutes(mins ~/ 60, mins % 60);
    final at = DateTime.now().add(Duration(minutes: mins));
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '$dur · $hh:$mm';
  }

  static int _progressPct(PrinterStatus s) {
    final p = s.progress ?? 0;
    final pct = p <= 1 ? (p * 100).round() : p.round();
    return pct.clamp(0, 100);
  }
}
