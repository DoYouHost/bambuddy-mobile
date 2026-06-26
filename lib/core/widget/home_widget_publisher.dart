import 'package:home_widget/home_widget.dart';

import '../../l10n/app_localizations.dart';
import '../models/printer_status.dart';
import '../notifications/hms_catalog.dart';

/// Publishes the state of one selected printer to the native home screen widget
/// (`BambuddyWidgetProvider`). Fed from TWO sources: the UI provider in the foreground
/// ([printerStatusesProvider]) and the background isolate (foreground service). Both call
/// [publish] on every fresh frame — `home_widget` writes data to shared SharedPreferences
/// and updates the widget.
///
/// Intentionally simple: the widget shows ONE printer (prefers one actively printing;
/// otherwise, the first by `id`). Dynamic data (names, status label) are already localized
/// from Dart — the native side doesn't translate them, only handles layout and
/// the status dot color (by `status_key`).
class HomeWidgetPublisher {
  /// Name of the [AppWidgetProvider] class on the Android side (package inferred from
  /// applicationId). `home_widget` uses it for `updateWidget`.
  static const String _androidProvider = 'BambuddyWidgetProvider';

  /// Status keys — must match color map in Kotlin.
  static const String _kPrinting = 'printing';
  static const String _kPaused = 'paused';
  static const String _kFinished = 'finished';
  static const String _kFailed = 'failed';
  static const String _kIdle = 'idle';
  static const String _kOffline = 'offline';
  static const String _kError = 'error';

  /// Saves the selected printer's state and updates the widget. Safe to call frequently —
  /// the plugin itself debounces writes, and `updateWidget` is cheap.
  ///
  /// [describeHms] — HMS error description from catalog (foreground: `HmsCatalog.instance`,
  /// background: isolate's local catalog). [fetchCover] — fetches print cover to file
  /// (authenticated with camera token); differs per isolate, so injected.
  /// Both optional — without them, widget simply skips HMS error/thumbnail.
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

      // Active HMS error overrides status (red dot + error content),
      // but we still show progress/ETA if the printer is printing anyway.
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

      // Fetch cover only during printing and only if server provides `cover_url`.
      // Skip during calibration phases (`auto_cali_*`) — those have no cover,
      // so otherwise the widget would show the previous print's thumbnail.
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

  /// The first "displayable" HMS error (severity 1..4 / with content — see
  /// [hmsIsDisplayable]), or `null`. Same criteria as the printer card.
  static HmsError? _topHmsError(
    PrinterStatus s,
    String? Function(HmsError)? describeHms,
  ) {
    for (final e in s.hmsErrors ?? const <HmsError>[]) {
      if (hmsIsDisplayable(e, description: describeHms?.call(e))) return e;
    }
    return null;
  }

  /// Layers as "X/Y" during printing, if server provides both fields. Otherwise empty.
  static String _layers(PrinterStatus s, String key) {
    if (key != _kPrinting && key != _kPaused) return '';
    final cur = s.layerNum;
    final total = s.totalLayers;
    if (cur == null || total == null || total <= 0) return '';
    return '$cur/$total';
  }

  /// Selects printer to show: first one actively printing (connected),
  /// otherwise the first by ascending `id`. null if no printers.
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

  /// Print name to show: when printing — current file (or stage if progress not yet available);
  /// when not printing — empty (UI hides the row).
  static String _printName(
    PrinterStatus s,
    AppLocalizations l10n,
    String key,
  ) {
    if (key != _kPrinting && key != _kPaused) return '';
    final name = s.currentPrint ?? s.gcodeFile;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    // Prep phase without file name — show stage if server provides it.
    return s.stgCurName?.trim() ?? '';
  }

  /// ETA row: remaining time + finish time (HH:mm). Empty outside printing or if
  /// server doesn't provide remaining time. Format matches the printer card
  /// (`durationMinutes`/`durationHoursMinutes`).
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
